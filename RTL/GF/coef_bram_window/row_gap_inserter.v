// =============================================================================
// row_gap_inserter.v
//
// Synchronizer between mapped_coef_gen_top and update_top.
//
// Problem: update_flow requires >=8 blank clock cycles (valid=0) between
//          consecutive rows so its x_counter can free-run from width-1
//          through width+6 and trigger a y_counter increment.
//          The mapped_coef_gen_top pipeline can compress/shift blanking
//          gaps, leaving insufficient gap for update_flow.
//
// Solution: This module buffers incoming valid data into a FIFO, and only
//           starts emitting a row once the FIFO has at least `width`
//           elements — guaranteeing an uninterrupted burst of `width`
//           valid outputs. After each row, it inserts exactly GAP_CYCLES
//           blank cycles.
//
// CRITICAL: Once a row starts emitting, it MUST complete without any
//           valid_out=0 gaps.  update_flow interprets ANY mid-row gap
//           (valid_in=0 near x >= width-1) as a row boundary.
//
// Implementation: Uses simple_dual_port_bram for synthesizable BRAM inference.
// Data is split across multiple BRAM instances (max 32 bits each) since each
// 36K BRAM supports up to 36-bit wide data.  156 bits / 32 = 5 BRAMs.
//
// Pipeline: mapped_coef_gen_top -> row_gap_inserter -> update_top
// =============================================================================
module row_gap_inserter #(
    parameter DATA_WIDTH = 15+17+14+17+15+15+17+14+17+15,  // curr (78) + prev (78) = 156 bits total
    parameter GAP_CYCLES = 8,                                // blank cycles between rows
    parameter FIFO_DEPTH = 4096                              // must be >= max row width (1280)
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [2:0]              layer_config,

    // Input side (from mapped_coef_gen_top)
    input  wire                    valid_in,
    input  wire [DATA_WIDTH-1:0]   data_in,

    // Output side (to update_top)
    output reg                     valid_out,
    output reg  [DATA_WIDTH-1:0]   data_out
);

    localparam ADDR_W = $clog2(FIFO_DEPTH);  // 12 for 4096

    // --------------------------------------------------------
    // Dynamic Width Decoding
    // --------------------------------------------------------
    reg [11:0] current_width;

    always @(*) begin
        case (layer_config)
            3'd0: current_width = 12'd1280;
            3'd1: current_width = 12'd640;
            3'd2: current_width = 12'd320;
            3'd3: current_width = 12'd160;
            3'd4: current_width = 12'd80;
            default: current_width = 12'd1280;
        endcase
    end

    // --------------------------------------------------------
    // FIFO Pointers and Count
    // --------------------------------------------------------
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    reg [ADDR_W:0]   fifo_count;   // extra bit for full detection

    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    // Can we start a new row?  Need at least current_width pixels in FIFO.
    wire row_ready = (fifo_count >= {1'b0, current_width});

    // --------------------------------------------------------
    // FIFO Storage: single URAM instance (156 bits × 4K deep)
    // URAM is 72-bit native; Vivado cascades 3 URAMs wide for 156 bits.
    // Saves ~20 BRAM36s compared to 5 × 32-bit BRAMs.
    // --------------------------------------------------------
    wire [DATA_WIDTH-1:0] bram_rd_data;

    simple_dual_port_uram #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_W)
    ) u_uram (
        .clk     (clk),
        .we      (valid_in && !fifo_full),
        .wr_addr (wr_ptr),
        .wr_data (data_in),
        .rd_addr (rd_ptr),
        .rd_data (bram_rd_data)
    );

    // --------------------------------------------------------
    // Write Pointer
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_W{1'b0}};
        end else if (valid_in && !fifo_full) begin
            wr_ptr <= wr_ptr + 1'b1;   // natural wrap at 2^ADDR_W
        end
    end

    // --------------------------------------------------------
    // Output FSM States
    // --------------------------------------------------------
    localparam S_WAIT    = 2'd0;   // Wait until FIFO has a full row
    localparam S_PREFETCH= 2'd1;   // 1-cycle BRAM read latency wait
    localparam S_EMIT    = 2'd2;   // Emit row pixels (uninterrupted)
    localparam S_GAP     = 2'd3;   // Insert blanking gap between rows

    reg [1:0]  state;
    reg [11:0] x_out_cnt;    // column counter for output
    reg [3:0]  gap_cnt;      // blanking gap counter

    // Read pointer advances in PREFETCH and during EMIT (except last pixel).
    // PREFETCH reads entry 0. EMIT reads entries 1..W-1.
    // Total reads per row = 1 + (W-1) = W. Correct.
    wire last_emit_pixel = (state == S_EMIT) && (x_out_cnt == current_width - 12'd1);
    wire do_read = (state == S_PREFETCH) || ((state == S_EMIT) && !last_emit_pixel);

    // --------------------------------------------------------
    // Read Pointer
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= {ADDR_W{1'b0}};
        end else if (do_read) begin
            rd_ptr <= rd_ptr + 1'b1;   // natural wrap at 2^ADDR_W
        end
    end

    // --------------------------------------------------------
    // FIFO Count Tracking
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_count <= 0;
        end else begin
            case ({(valid_in && !fifo_full), do_read})
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= fifo_count - 1;
                default: fifo_count <= fifo_count; // 2'b00 or 2'b11
            endcase
        end
    end

    // --------------------------------------------------------
    // Output Control FSM
    //
    // BRAM has 1-cycle read latency:
    //   Cycle N  : rd_ptr = A presented to BRAM
    //   Cycle N+1: bram_rd_data = mem[A]
    //
    // So we add a PREFETCH state: present rd_ptr[0] to BRAM,
    // then in EMIT the data is available 1 cycle later.
    // During EMIT, rd_ptr advances each cycle so the NEXT
    // pixel's data arrives on the following cycle.
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_WAIT;
            x_out_cnt <= 12'd0;
            gap_cnt   <= 4'd0;
            valid_out <= 1'b0;
            data_out  <= {DATA_WIDTH{1'b0}};
        end else begin
            case (state)
                // --------------------------------------------------
                // WAIT: Hold until FIFO has at least one full row.
                //       This guarantees the EMIT phase never starves.
                // --------------------------------------------------
                S_WAIT: begin
                    valid_out <= 1'b0;
                    if (row_ready) begin
                        // rd_ptr is already pointing to first unread entry.
                        // Transition to PREFETCH: BRAM will read mem[rd_ptr]
                        // and rd_ptr will advance via do_read.
                        state <= S_PREFETCH;
                    end
                end

                // --------------------------------------------------
                // PREFETCH: Wait 1 cycle for BRAM read latency.
                //           rd_ptr was presented in this cycle.
                //           rd_ptr advances (do_read=1) so next addr
                //           is ready for the first EMIT cycle.
                // --------------------------------------------------
                S_PREFETCH: begin
                    valid_out <= 1'b0;
                    state     <= S_EMIT;
                end

                // --------------------------------------------------
                // EMIT: Output one pixel per cycle for `width` cycles.
                //       bram_rd_data holds the pixel that was read
                //       1 cycle ago. rd_ptr advances each cycle to
                //       prefetch the next pixel.
                // --------------------------------------------------
                S_EMIT: begin
                    valid_out <= 1'b1;
                    data_out  <= bram_rd_data;

                    if (x_out_cnt == current_width - 12'd1) begin
                        // End of row — start blanking gap
                        x_out_cnt <= 12'd0;
                        gap_cnt   <= GAP_CYCLES[3:0];
                        state     <= S_GAP;
                    end else begin
                        x_out_cnt <= x_out_cnt + 12'd1;
                    end
                end

                // --------------------------------------------------
                // GAP: Insert exactly GAP_CYCLES blank cycles, then
                //      go back to WAIT (which checks for next row).
                // --------------------------------------------------
                S_GAP: begin
                    valid_out <= 1'b0;
                    if (gap_cnt == 4'd1) begin
                        gap_cnt <= 4'd0;
                        state   <= S_WAIT;
                    end else begin
                        gap_cnt <= gap_cnt - 4'd1;
                    end
                end

                default: state <= S_WAIT;
            endcase
        end
    end

endmodule
