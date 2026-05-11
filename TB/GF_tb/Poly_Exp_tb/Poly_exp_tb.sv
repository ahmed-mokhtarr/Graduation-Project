`timescale 1ns / 1ps

// =============================================================
// Poly-Expansion Top Testbench
//
// Output files produced:
//   tb_vert_outputs.txt  — vertical filter outputs (one line per valid pixel)
//                          format: v_p0  v_p1  v_p2
//   tb_r_outputs.txt     — final r coefficients (one line per valid output pixel)
//                          format: r2  r3  r4  r5  r6
// =============================================================
module tb_poly_exp_top();

    // --------------------------------------------------------
    // Image Parameters
    // --------------------------------------------------------
    parameter IMG_WIDTH  = 1280;
    parameter IMG_HEIGHT = 720;
    parameter NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 3600 pixels

    // --------------------------------------------------------
    // Testbench Signals
    // --------------------------------------------------------
    logic        clk;
    logic        rst_n;

    logic        vsync_in;
    logic        hsync_in;
    logic        valid_in;
    logic [2:0]  layer_config;
    logic [7:0]  pixel_in;
    logic [11:0] x_counter;  // column index driven by TB
    logic [11:0] y_counter;  // row    index driven by TB

    logic signed [14:0] r2_out;   // OUT_R2_W = 15
    logic signed [16:0] r3_out;   // OUT_R3_W = 17
    logic signed [13:0] r4_out;   // OUT_R4_W = 14
    logic signed [16:0] r5_out;   // OUT_R5_W = 17
    logic signed [14:0] r6_out;   // OUT_R6_W = 15
    logic               valid_out;

    // Memory array to hold the hex image data
    logic [7:0] image_mem [0 : NUM_PIXELS-1];

    // --------------------------------------------------------
    // Load Image Data
    // --------------------------------------------------------
    initial begin
        $readmemh("output_L0_hex.txt", image_mem);
        $display("Successfully loaded image data into testbench memory.");
    end

    // --------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // --------------------------------------------------------
    poly_exp_top uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .vsync_in     (vsync_in),
        .hsync_in     (hsync_in),
        .valid_in     (valid_in),
        .layer_config (layer_config),
        .pixel_in     (pixel_in),
        .x_counter    (x_counter),
        .y_counter    (y_counter),
        .r2_out       (r2_out),
        .r3_out       (r3_out),
        .r4_out       (r4_out),
        .r5_out       (r5_out),
        .r6_out       (r6_out),
        .valid_out    (valid_out)
    );

    // --------------------------------------------------------
    // Clock Generation (100 MHz → 10 ns period)
    // --------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --------------------------------------------------------
    // File handles
    // --------------------------------------------------------
    // File I/O for debugging & verification
    int vert_file;
    int r_file;
    int r_raw_file;
    int vert_count;
    int r_count;

    initial begin
        // --- vertical filter output file ---
        vert_file = $fopen("tb_vert_outputs.txt", "w");
        if (vert_file == 0) begin
            $display("ERROR: Could not open tb_vert_outputs.txt");
            $finish;
        end
        // Header so Python knows the column order
        $fwrite(vert_file, "# v_p0  v_p1  v_p2\n");

        // --- r-coefficient output file ---
        r_file = $fopen("tb_r_outputs.txt", "w");
        if (r_file == 0) begin
            $display("ERROR: Could not open tb_r_outputs.txt");
            $finish;
        end
        // Header so Python knows the column order
        $fwrite(r_file, "# r2  r3  r4  r5  r6\n");

        // --- raw r-coefficient output file ---
        r_raw_file = $fopen("tb_r_raw_outputs.txt", "w");
        if (r_raw_file == 0) begin
            $display("ERROR: Could not open tb_r_raw_outputs.txt");
            $finish;
        end
        $fwrite(r_raw_file, "# r2_raw  r3_raw  r4_raw  r5_raw  r6_raw\n");

        vert_count = 0;
        r_count    = 0;
    end

    // --------------------------------------------------------
    // Capture vertical filter outputs
    //   Hierarchical references into the DUT:
    //     uut.v_valid_p0  — asserted when vertical MACs produce valid data
    //     uut.v_p0_raw    — p0 vertical output  (V_P0_W = 29 bits)
    //     uut.v_p1_raw    — p1 vertical output  (V_P1_W = 27 bits)
    //     uut.v_p2_raw    — p2 vertical output  (V_P2_W = 26 bits)
    //
    //   All three valids are always identical (same pipeline depth),
    //   so we only need v_valid_p0 as the trigger.
    //   We log exactly NUM_PIXELS samples (one per image pixel).
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (uut.v_valid_p0 && vert_count < NUM_PIXELS) begin
            $fwrite(vert_file, "%0d %0d %0d\n",
                    $signed(uut.v_p0_raw),
                    $signed(uut.v_p1_raw),
                    $signed(uut.v_p2_raw));
            vert_count = vert_count + 1;
        end
    end

    // --------------------------------------------------------
    // Capture final r-coefficient outputs
    //   Logged when valid_out is asserted.
    //   The raw (pre-normalisation) widths are also accessible
    //   hierarchically if needed, but we log the normalised outputs here.
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (valid_out && r_count < NUM_PIXELS) begin
            $fwrite(r_file, "%0d %0d %0d %0d %0d\n",
                    r2_out, r3_out, r4_out, r5_out, r6_out);
            $fwrite(r_raw_file, "%0d %0d %0d %0d %0d\n",
                    $signed(uut.r2_raw), $signed(uut.r3_raw), $signed(uut.r4_raw), $signed(uut.r5_raw), $signed(uut.r6_raw));
            r_count = r_count + 1;
        end
    end

    // --------------------------------------------------------
    // Stimulus Generation
    // --------------------------------------------------------
    initial begin
        // 1. Initialise & reset
        rst_n        = 0;
        vsync_in     = 0;
        hsync_in     = 0;
        valid_in     = 0;
        pixel_in     = 8'd0;
        x_counter    = 12'd0;
        y_counter    = 12'd0;
        layer_config = 3'd0;  // Layer 4 → 80×45

        #20;
        rst_n = 1;
        #20;

        // 2. Active frame
        $display("Starting video stream...");
        @(posedge clk);
        vsync_in <= 1;

        // Loop through every row, then 5 extra rows so bottom boundary flushes.
        // The extra rows are driven with valid_in=1 and pixel=0 so the pipeline
        // keeps running and the last rows reach the horizontal MAC stage.
        for (int y = 0; y < IMG_HEIGHT + 5; y++) begin

            // Drive y_counter one cycle before the row starts so the DUT
            // sees the correct value on the first pixel of each row.
            @(posedge clk);
            y_counter <= y[11:0];

            for (int x = 0; x < IMG_WIDTH + 5; x++) begin
                @(posedge clk);
                x_counter <= x[11:0];
                hsync_in  <= 0;

                // Only drive real pixel data for actual image rows;
                // feed zeros for the extra flush rows.
                if (y < IMG_HEIGHT && x < IMG_WIDTH) begin
                    valid_in <= 1;
                    pixel_in <= image_mem[(y * IMG_WIDTH) + x];
                end else if (x >= IMG_WIDTH) begin
                    // Horizontal blanking flush (stop vertical line buffer)
                    valid_in <= 0;
                    pixel_in <= 8'd0;
                end else begin
                    // Vertical flush rows
                    valid_in <= 1;
                    pixel_in <= 8'd0;
                end
            end

            // End-of-row blanking pulse
            @(posedge clk);
            hsync_in  <= 1;
            valid_in  <= 0;
            x_counter <= 12'd0;
        end

        // 3. End of frame
        @(posedge clk);
        vsync_in <= 0;

        // Wait for final pipeline stages to drain (3 cycles deep × safety margin)
        #200;

        $display("Simulation complete.");
        $display("  Vertical outputs captured : %0d / %0d", vert_count, NUM_PIXELS);
        $display("  R-coeff outputs captured  : %0d / %0d", r_count,    NUM_PIXELS);
        $fclose(vert_file);
        $fclose(r_file);
        $fclose(r_raw_file);

        $stop;
    end

endmodule