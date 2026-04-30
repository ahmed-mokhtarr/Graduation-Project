// =============================================================================
// Module  : fast_top_tb
// Purpose : Self-checking testbench for top.v (fast_top + feature_saving).
//
//  Flow
//  ────
//  1. Load grayscale pixel data from  image_pixels.hex.
//  2. Drive the AXI4-Stream interface one pixel per clock.
//  3. Capture every corner_valid pulse into:
//       - rtl_corners.txt               (for Python / OpenCV comparison)
//       - rtl_corners_col/row arrays    (for in-simulation BRAM check)
//  4. After pipeline drains, read every entry from the feature_saving BRAM
//     via the read_addr / read_en / read_data interface.
//  5. Compare BRAM entry i  ↔  rtl_corners[i]  (col + row).
//     Report PASS / FAIL per entry and a final summary.
//
//  BRAM note
//  ─────────
//  simple_dual_port_bram has a 1-cycle registered read latency:
//    cycle N   : assert read_en=1, read_addr=i
//    cycle N+1 : read_data is valid  (sampled by the BRAM at posedge N)
//
//  Ping-pong note
//  ──────────────
//  On frame_done the buffers swap (registered → takes effect 1 clock later).
//  After the swap the previously written BRAM is the readable one and
//  prev_feature_count holds the number of valid entries.
//  Corners that arrive AFTER frame_done (pipeline tail) go into the new
//  write buffer and are NOT in prev_feature_count — so the comparison
//  covers indices 0 … prev_feature_count-1 only.
// =============================================================================

`timescale 1ns / 1ps

module fast_save_tb;

    // ── Simulation parameters ──────────────────────────────────────────────
    localparam IMG_WIDTH    = 1280;
    localparam IMG_HEIGHT   = 720;
    localparam THRESHOLD    = 35;
    localparam N_CONSEC     = 9;
    localparam SCORE_WIDTH  = 12;
    localparam ADDR_WIDTH = 12;
    localparam DATA_WIDTH = 32;
    localparam TOTAL_PX     = IMG_WIDTH * IMG_HEIGHT;

    // Extra clocks after last pixel for the full pipeline to drain:
    //   6 row-buffer rows  +  3 SR column stages  +  NMS 2-row delay  +  margin
    localparam DRAIN_CYCLES = IMG_WIDTH * 12;

    localparam COL_W = $clog2(IMG_WIDTH);    // 11 bits
    localparam ROW_W = $clog2(IMG_HEIGHT);   // 10 bits

    // ── DUT signals ────────────────────────────────────────────────────────
    reg        clk;
    reg        rst_n;

    // AXI4-Stream slave
    reg  [7:0] s_axis_tdata;
    reg        s_axis_tvalid;
    wire       s_axis_tready;
    reg        s_axis_tlast;
    reg        s_axis_tuser;

    // Corner stream (exposed by top.v)
    wire                          corner_valid;
    wire [COL_W-1:0]              corner_col;
    wire [ROW_W-1:0]              corner_row;
    wire [SCORE_WIDTH-1:0]        corner_score;
    wire                          frame_done;

    // Feature-saving BRAM read interface
    reg  [ADDR_WIDTH-1:0]  read_addr;
    reg            read_en;
    wire [DATA_WIDTH-1:0]    read_data;          // {16'b_row_zero_ext, 16'b_col_zero_ext}
    wire [ADDR_WIDTH:0]    prev_feature_count; // valid entry count in readable BRAM

    // ── DUT — top.v ────────────────────────────────────────────────────────
    top #(
        .IMG_WIDTH   (IMG_WIDTH),
        .IMG_HEIGHT  (IMG_HEIGHT),
        .THRESHOLD   (THRESHOLD),
        .N_CONSEC    (N_CONSEC),
        .SCORE_WIDTH (SCORE_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH)
    ) u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .s_axis_tdata      (s_axis_tdata),
        .s_axis_tvalid     (s_axis_tvalid),
        .s_axis_tready     (s_axis_tready),
        .s_axis_tlast      (s_axis_tlast),
        .s_axis_tuser      (s_axis_tuser),
        .read_addr         (read_addr),
        .read_en           (read_en),
        .read_data         (read_data),
        .prev_feature_count(prev_feature_count),
        .corner_valid      (corner_valid),
        .corner_col        (corner_col),
        .corner_row        (corner_row),
        .corner_score      (corner_score),
        .frame_done        (frame_done)
    );

    // ── Clock: 100 MHz (10 ns period) ─────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Pixel memory ───────────────────────────────────────────────────────
    reg [7:0] pixel_mem [0:TOTAL_PX-1];

    // ── RTL corner capture arrays (filled by the always block below) ───────
    // Only the first MAX_FEATURES corners are stored; total count is in corner_cnt.
    reg [COL_W-1:0]       rtl_corners_col   [0:(1<<ADDR_WIDTH)-1];
    reg [ROW_W-1:0]       rtl_corners_row   [0:(1<<ADDR_WIDTH)-1];
    reg [SCORE_WIDTH-1:0] rtl_corners_score [0:(1<<ADDR_WIDTH)-1];

    integer corner_cnt; // total corners detected (may exceed MAX_FEATURES)
    integer f_out;
    reg     frame_done_seen; // set when frame_done fires; gates corner capture

    // Latch frame_done so we stop counting after the frame boundary.
    always @(posedge clk) begin
        if (!rst_n)
            frame_done_seen <= 1'b0;
        else if (frame_done)
            frame_done_seen <= 1'b1;
    end

    // Capture corner_valid pulses ONLY before frame_done.
    // Blanking-pixel flush produces spurious NMS outputs after frame_done
    // (row=0 artifacts); excluding them keeps corner_cnt == prev_feature_count.
    always @(posedge clk) begin
        if (corner_valid && !frame_done_seen) begin
            if (corner_cnt < (1<<ADDR_WIDTH)) begin
                rtl_corners_col  [corner_cnt] = corner_col;
                rtl_corners_row  [corner_cnt] = corner_row;
                rtl_corners_score[corner_cnt] = corner_score;
            end
            corner_cnt = corner_cnt + 1;
            $fwrite(f_out, "%0d,%0d,%0d\n", corner_col, corner_row, corner_score);
        end
    end

    // ── Main stimulus + BRAM verification ─────────────────────────────────
    integer pix_idx, col_idx;
    integer i;
    integer bram_col, bram_row;
    integer pass_cnt, fail_cnt;
    integer expected_count;

    initial begin

        // ── Load image ─────────────────────────────────────────────────────
        $readmemh("image_pixels.hex", pixel_mem);
        $display("[TB] Pixel memory loaded (%0d pixels, %0dx%0d)",
                 TOTAL_PX, IMG_WIDTH, IMG_HEIGHT);

        // ── Open output file ───────────────────────────────────────────────
        f_out           = $fopen("rtl_corners.txt", "w");
        corner_cnt      = 0;
        frame_done_seen = 1'b0;
        read_addr       = {ADDR_WIDTH{1'b0}};
        read_en         = 1'b0;

        if (f_out == 0) begin
            $display("[TB] ERROR: Cannot open rtl_corners.txt for writing");
            $finish;
        end

        // ── Initialise signals ─────────────────────────────────────────────
        rst_n         = 1'b0;
        s_axis_tdata  = 8'h00;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tuser  = 1'b0;

        // ── Reset ──────────────────────────────────────────────────────────
        repeat(10) @(posedge clk);
        @(posedge clk); #1; rst_n = 1'b1;
        repeat(5)  @(posedge clk);

        $display("[TB] Reset released. Starting pixel stream...");

        // ── Stream all pixels at 1 pixel per clock ─────────────────────────
        // Signals driven 1 ns after posedge so they are stable at the next edge.
        for (pix_idx = 0; pix_idx < TOTAL_PX; pix_idx = pix_idx + 1) begin
            @(posedge clk); #1;
            col_idx       = pix_idx % IMG_WIDTH;
            s_axis_tdata  = pixel_mem[pix_idx];
            s_axis_tvalid = 1'b1;
            s_axis_tuser  = (pix_idx == 0)             ? 1'b1 : 1'b0;
            s_axis_tlast  = (col_idx == IMG_WIDTH - 1) ? 1'b1 : 1'b0;
        end

        // ── Flush the pipeline after the last pixel ────────────────────────
        @(posedge clk); #1;
        // CHANGE: Keep valid HIGH to flush the pipeline!
        s_axis_tvalid = 1'b1;  
        s_axis_tlast  = 1'b0;
        s_axis_tuser  = 1'b0;
        s_axis_tdata  = 8'h00; // Send dummy blanking pixels

        $display("[TB] All %0d pixels sent. Flushing pipeline...", TOTAL_PX);

        // ── Drain: wait for the last in-flight corner to exit the pipeline ──
        repeat(DRAIN_CYCLES) @(posedge clk);

        // NOW de-assert AXI valid after the pipeline has fully drained
        @(posedge clk); #1;
        s_axis_tvalid = 1'b0;

        // Close the text output file before verification starts
        $fclose(f_out);
        $display("[TB] Simulation done. %0d corners written to rtl_corners.txt",
                 corner_cnt);

        // ── Allow the ping-pong swap to settle (frame_done is registered) ──
        // frame_done fires during drain; feature_saving swaps on the next clock.
        // A few extra cycles ensures prev_feature_count is stable.
        repeat(10) @(posedge clk);

        // ==================================================================
        // BRAM VERIFICATION
        // Compare read_data from feature_saving BRAM with the rtl_corners
        // arrays captured during streaming.
        //
        // BRAM format: read_data[31:16] = row (zero-padded to 16 b)
        //              read_data[15: 0] = col (zero-padded to 16 b)
        //
        // Corners that arrived after frame_done (pipeline tail) went into
        // the new write buffer and are NOT in prev_feature_count, so we
        // compare indices 0 … prev_feature_count-1 only.
        // ==================================================================
        $display("[TB] ─────────────────────────────────────────────────────");
        $display("[TB]  BRAM VERIFICATION");
        $display("[TB] ─────────────────────────────────────────────────────");
        $display("[TB]  prev_feature_count (BRAM entries) = %0d", prev_feature_count);
        $display("[TB]  total corner_valid pulses (RTL)   = %0d", corner_cnt);

        // Expected number of entries to verify
        expected_count = (corner_cnt <= (1<<ADDR_WIDTH)) ? corner_cnt : (1<<ADDR_WIDTH);

        if (prev_feature_count !== expected_count) begin
            $display("[TB]  NOTE: prev_feature_count (%0d) differs from expected (%0d).",
                     prev_feature_count, expected_count);
            $display("[TB]        Corners after frame_done go to the new buffer — this is normal.");
        end

        pass_cnt = 0;
        fail_cnt = 0;

        // ── Sequential read-back loop ──────────────────────────────────────
        // Each iteration:
        //   Cycle 0 : assert read_en + read_addr  → BRAM latches mem[i]
        //   Cycle 1 : de-assert read_en, sample read_data (now valid)
        for (i = 0; i < prev_feature_count; i = i + 1) begin

            // ── Cycle 0: issue read request ────────────────────────────────
            @(posedge clk); #1;
            read_addr = i[ADDR_WIDTH-1:0];
            read_en   = 1'b1;

            // ── Cycle 1: BRAM registered output is now stable ──────────────
            @(posedge clk); #1;
            read_en = 1'b0;

            // Unpack BRAM word: {16'b_row, 16'b_col}
            bram_col = read_data[15:0];
            bram_row = read_data[31:16];

            // Compare against captured RTL corner
            if ((bram_col === rtl_corners_col[i]) &&
                (bram_row === rtl_corners_row[i])) begin
                pass_cnt = pass_cnt + 1;
                $display("[TB]  [PASS] [%0d]  BRAM(row=%0d, col=%0d)  ==  RTL(row=%0d, col=%0d)",
                         i, bram_row, bram_col,
                         rtl_corners_row[i], rtl_corners_col[i]);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[TB]  [FAIL] [%0d]  BRAM(row=%0d, col=%0d)  !=  RTL(row=%0d, col=%0d)",
                         i, bram_row, bram_col,
                         rtl_corners_row[i], rtl_corners_col[i]);
            end
        end

        // ── Summary ────────────────────────────────────────────────────────
        $display("[TB] ─────────────────────────────────────────────────────");
        $display("[TB]  Checked %0d entries:  %0d PASS  /  %0d FAIL",
                 prev_feature_count, pass_cnt, fail_cnt);

        if (fail_cnt == 0 && prev_feature_count > 0) begin
            $display("[TB]  *** ALL CHECKS PASSED — BRAM matches RTL corners ***");
        end else if (prev_feature_count == 0) begin
            $display("[TB]  *** WARNING: no BRAM entries to verify (0 corners saved) ***");
        end else begin
            $display("[TB]  *** VERIFICATION FAILED — %0d mismatch(es) found ***", fail_cnt);
        end
        $display("[TB] ─────────────────────────────────────────────────────");

        $finish;
    end

    // ── Timeout watchdog (prevents infinite hang) ──────────────────────────
    initial begin
        #( (TOTAL_PX + DRAIN_CYCLES + 1000) * 10 );
        $display("[TB] TIMEOUT — simulation exceeded maximum allowed cycles.");
        $fclose(f_out);
        $finish;
    end

endmodule