// =============================================================================
// retiming.v
//
// Retiming / Dispatch Module
//
// Monitors the Memory Read Module (MRM) `data_ready` signal.
// When asserted during the active frame, it captures the two valid pixels
// (curr_data_out, prev_data_out) and drives them — together with pixel-
// position counters — to two parallel poly_exp_top instances.
//
// Counter generation (mirrors Poly_exp_tb.sv exactly):
//   x_counter : 0 .. (W-1) per active row, then W..W+4 for horizontal flush
//   y_counter : 0 .. (H-1) active rows, then H..H+4 for 5 vertical flush rows
//
// Flush behaviour (required by poly_exp_top boundary reflection logic):
//   • Horizontal flush  : after each row's W active pixels, 5 extra columns
//                         (x = W..W+4) are driven with valid=1, pixel=0 so
//                         the right-boundary reflection populates correctly.
//   • Vertical flush    : 5 extra rows (y = H..H+4) of W+5 pixels each.
//   Both flush phases run free-running (not gated by data_ready) so the
//   poly pipeline is never starved.
// =============================================================================
module retiming #(
    parameter PIXEL_WIDTH  = 8,
    parameter MAX_WIDTH    = 1280,
    parameter MAX_HEIGHT   = 720
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // ── MRM interface ──────────────────────────────────────────────────────
    input  wire                   data_ready,          // high = active pixel valid
    output wire                   ready,               // high = ready to accept pixel
    input  wire [PIXEL_WIDTH-1:0] curr_data_out,       // current  frame pixel
    input  wire [PIXEL_WIDTH-1:0] prev_data_out,       // previous frame pixel

    // ── Layer configuration (shared) ───────────────────────────────────────
    input  wire [2:0]             layer_config,

    // ── Outputs to poly_exp_top (curr channel) ─────────────────────────────
    output reg                    curr_valid_in,
    output reg  [PIXEL_WIDTH-1:0] curr_pixel_in,
    output reg  [11:0]            curr_x_counter,
    output reg  [11:0]            curr_y_counter,

    // ── Outputs to poly_exp_top (prev channel) ─────────────────────────────
    output reg                    prev_valid_in,
    output reg  [PIXEL_WIDTH-1:0] prev_pixel_in,
    output reg  [11:0]            prev_x_counter,
    output reg  [11:0]            prev_y_counter,

    // ── Layer dimensions (decoded, for external use) ────────────────────────
    output wire [10:0]            frame_width,
    output wire [10:0]            frame_height,

    // ── Frame done strobe (one cycle after last flush pixel sent) ──────────
    output reg                    frame_done,

    // ── Frame start strobe (IDLE→ACT transition — new layer begins) ────────
    output reg                    frame_start
);

    // =========================================================================
    // Layer dimension decode — combinational lookup, then LATCHED at IDLE→ACT
    // so that a mid-VFLUSH layer_config change cannot corrupt end-conditions.
    // =========================================================================
    reg [10:0] f_width_comb;
    reg [10:0] f_height_comb;

    always @(*) begin
        case (layer_config)
            3'd0: begin f_width_comb = 11'd1280; f_height_comb = 11'd720; end
            3'd1: begin f_width_comb = 11'd640;  f_height_comb = 11'd360; end
            3'd2: begin f_width_comb = 11'd320;  f_height_comb = 11'd180; end
            3'd3: begin f_width_comb = 11'd160;  f_height_comb = 11'd90;  end
            3'd4: begin f_width_comb = 11'd80;   f_height_comb = 11'd45;  end
            default: begin f_width_comb = 11'd1280; f_height_comb = 11'd720; end
        endcase
    end

    // Latched dimensions — stable throughout ACT / HFLUSH / VFLUSH / DONE
    reg [10:0] f_width;
    reg [10:0] f_height;
    // (latched inside the FSM IDLE→ACT transition below)

    assign frame_width  = f_width;
    assign frame_height = f_height;

    // =========================================================================
    // Internal counters
    //   x_cnt : 0 .. W+4   (W active + 5 horizontal flush columns)
    //   y_cnt : 0 .. H+4   (H active + 5 vertical   flush rows)
    // =========================================================================
    reg [11:0] x_cnt;
    reg [11:0] y_cnt;

    // One-wide column-end flags (use LATCHED dimensions)
    wire x_active_last = (x_cnt == {1'b0, f_width} - 12'd1);   // last active col
    wire x_row_end     = (x_cnt == {1'b0, f_width} + 12'd4);   // last flush col
    wire y_active_last = (y_cnt == {1'b0, f_height} - 12'd1);  // last active row
    wire y_frame_end   = (y_cnt == {1'b0, f_height} + 12'd25); // last flush row

    // ── FSM ──────────────────────────────────────────────────────────────────
    // ACT  : active frame — data_ready gated, real pixels
    // HFLUSH: horizontal-flush columns after active pixels (x = W..W+4)
    //         zero pixel, valid=1, free-running
    // VFLUSH: full rows of zeros after last active row (y = H..H+25),
    //         each row also gets its own HFLUSH tail
    // DONE : pulse frame_done, back to IDLE
    localparam IDLE   = 3'd0;
    localparam ACT    = 3'd1;
    localparam HFLUSH = 3'd2;
    localparam VFLUSH = 3'd3;
    localparam DONE   = 3'd4;

    reg [2:0] state;
    assign ready = (state == IDLE) || (state == ACT);

    // =========================================================================
    // Helper task — drive both channels with the same pixel/counter
    // (inline macro-style; avoids duplicating every assignment)
    // =========================================================================
    // Not a real task — done via direct assignments below.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            x_cnt          <= 12'd0;
            y_cnt          <= 12'd0;
            f_width        <= 11'd80;
            f_height       <= 11'd45;
            curr_valid_in  <= 1'b0;
            curr_pixel_in  <= {PIXEL_WIDTH{1'b0}};
            curr_x_counter <= 12'd0;
            curr_y_counter <= 12'd0;
            prev_valid_in  <= 1'b0;
            prev_pixel_in  <= {PIXEL_WIDTH{1'b0}};
            prev_x_counter <= 12'd0;
            prev_y_counter <= 12'd0;
            frame_done     <= 1'b0;
            frame_start    <= 1'b0;
        end else begin
            // Default de-assert
            curr_valid_in <= 1'b0;
            prev_valid_in <= 1'b0;
            frame_done    <= 1'b0;
            frame_start   <= 1'b0;

            case (state)

                // ── Idle: wait for first pixel ─────────────────────────────
                IDLE: begin
                    x_cnt <= 12'd0;
                    y_cnt <= 12'd0;
                    if (data_ready) begin
                        // ── LATCH dimensions at processing start ──────────
                        f_width  <= f_width_comb;
                        f_height <= f_height_comb;
                        frame_start <= 1'b1;  // pulse: new layer processing begins
                        // Pixel (0,0)
                        curr_valid_in  <= 1'b1;
                        curr_pixel_in  <= curr_data_out;
                        curr_x_counter <= 12'd0;
                        curr_y_counter <= 12'd0;
                        prev_valid_in  <= 1'b1;
                        prev_pixel_in  <= prev_data_out;
                        prev_x_counter <= 12'd0;
                        prev_y_counter <= 12'd0;
                        x_cnt <= 12'd1;
                        state <= ACT;
                    end
                end

                // ── Active pixels (gated by data_ready) ────────────────────
                ACT: begin
                    if (data_ready) begin
                        curr_valid_in  <= 1'b1;
                        curr_pixel_in  <= curr_data_out;
                        curr_x_counter <= x_cnt;
                        curr_y_counter <= y_cnt;
                        prev_valid_in  <= 1'b1;
                        prev_pixel_in  <= prev_data_out;
                        prev_x_counter <= x_cnt;
                        prev_y_counter <= y_cnt;

                        if (x_active_last) begin
                            // End of active columns → horizontal flush
                            x_cnt <= {1'b0, f_width};  // x = W
                            state <= HFLUSH;
                        end else begin
                            x_cnt <= x_cnt + 12'd1;
                        end
                    end else begin
                        curr_valid_in  <= 1'b0;
                        curr_x_counter <= x_cnt;
                        curr_y_counter <= y_cnt;
                        prev_valid_in  <= 1'b0;
                        prev_x_counter <= x_cnt;
                        prev_y_counter <= y_cnt;
                    end
                end

                // ── Horizontal flush (x = W .. W+4, zero pixels) ───────────
                // Free-running: one col per clock, no data_ready dependency.
                HFLUSH: begin
                    curr_valid_in  <= 1'b0;   // blanking — valid=0 in hblank
                    curr_pixel_in  <= {PIXEL_WIDTH{1'b0}};
                    curr_x_counter <= x_cnt;
                    curr_y_counter <= y_cnt;
                    prev_valid_in  <= 1'b0;
                    prev_pixel_in  <= {PIXEL_WIDTH{1'b0}};
                    prev_x_counter <= x_cnt;
                    prev_y_counter <= y_cnt;

                    if (x_row_end) begin
                        // Row fully flushed
                        x_cnt <= 12'd0;
                        if (y_active_last) begin
                            // Last active row done → start vertical flush
                            y_cnt <= {1'b0, f_height};
                            state <= VFLUSH;
                        end else begin
                            y_cnt <= y_cnt + 12'd1;
                            state <= ACT;   // next row
                        end
                    end else begin
                        x_cnt <= x_cnt + 12'd1;
                    end
                end

                // ── Vertical flush (y = H..H+4, full rows of zeros) ────────
                // Runs free-running, valid=1, pixel=0.
                // Each row is W pixels wide (columns 0..W-1).
                // After each row, drive 5 extra h-blank cols (x=W..W+4)
                // with valid=0 to mimic original TB's end-of-row blanking.
                VFLUSH: begin
                    if (x_cnt < {1'b0, f_width}) begin
                        // Active-column portion of flush row
                        curr_valid_in  <= 1'b1;
                        curr_pixel_in  <= {PIXEL_WIDTH{1'b0}};
                        curr_x_counter <= x_cnt;
                        curr_y_counter <= y_cnt;
                        prev_valid_in  <= 1'b1;
                        prev_pixel_in  <= {PIXEL_WIDTH{1'b0}};
                        prev_x_counter <= x_cnt;
                        prev_y_counter <= y_cnt;

                        if (x_active_last) begin
                            x_cnt <= {1'b0, f_width};   // enter h-blank tail
                        end else begin
                            x_cnt <= x_cnt + 12'd1;
                        end
                    end else begin
                        // H-blank tail for this flush row (x = W..W+4)
                        curr_valid_in  <= 1'b0;
                        curr_pixel_in  <= {PIXEL_WIDTH{1'b0}};
                        curr_x_counter <= x_cnt;
                        curr_y_counter <= y_cnt;
                        prev_valid_in  <= 1'b0;
                        prev_pixel_in  <= {PIXEL_WIDTH{1'b0}};
                        prev_x_counter <= x_cnt;
                        prev_y_counter <= y_cnt;

                        if (x_row_end) begin
                            x_cnt <= 12'd0;
                            if (y_frame_end) begin
                                state      <= DONE;
                                frame_done <= 1'b1;
                            end else begin
                                y_cnt <= y_cnt + 12'd1;
                            end
                        end else begin
                            x_cnt <= x_cnt + 12'd1;
                        end
                    end
                end

                // ── Done ──────────────────────────────────────────────────
                DONE: begin
                    frame_done <= 1'b0;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
