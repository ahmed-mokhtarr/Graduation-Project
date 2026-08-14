module zoom_in #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter DLIMIT     = 12
)(
    input  wire        clk,
    input  wire        rst_n,

    // Interface with FSM
    input  wire [2:0]  curr_layer,
    input  wire        operation_start,
    output reg         zoom_done,

    // Interface with MRM flow FIFO
    input  wire [15:0] flow_data,       // [15:8]=dy, [7:0]=dx
    input  wire        flow_ready,
    output wire        flow_rd_en,

    // Interface with downstream (ready-only streaming, no tvalid)
    output wire [15:0] zoomed_flow_out, // [15:8]=dy, [7:0]=dx
    output wire        zoomed_data_ready, // High when zoomed_flow_out has valid unconsumed data
    input  wire        zoomed_tready
);

    // =========================================================================
    // Shift right by 3 and clip to [-15, +15]
    // Input: 9-bit signed zoomed value (before compensation)
    // Output: 8-bit signed clipped value
    // =========================================================================
    function [7:0] shift_clip;
        input signed [10:0] val;
        reg signed [10:0] shifted;
        reg signed [10:0] pos_limit;
        reg signed [10:0] neg_limit;
        begin
            shifted   = val >>> 3;
            pos_limit = DLIMIT;
            neg_limit = -DLIMIT;
            if (shifted > pos_limit)
                shift_clip = pos_limit[7:0];
            else if (shifted < neg_limit)
                shift_clip = neg_limit[7:0];
            else
                shift_clip = shifted[7:0];
        end
    endfunction

    // =========================================================================
    // Line Buffer BRAM (stores current row of input)
    // =========================================================================
    reg  [11:0] lb_waddr;
    reg  [11:0] lb_raddr;
    reg  [15:0] lb_din;
    reg         lb_we;
    wire [15:0] lb_rdata;

    simple_dual_port_bram #(
        .DATA_WIDTH(16),
        .ADDR_WIDTH(12)
    ) u_line_buffer (
        .clk     (clk),
        .we      (lb_we),
        .wr_addr (lb_waddr),
        .wr_data (lb_din),
        .rd_addr (lb_raddr),
        .rd_data (lb_rdata)
    );

    // =========================================================================
    // Next Row Buffer BRAM (stores 10/11 results for drain phase)
    // =========================================================================
    reg  [11:0] lb_nextrow_waddr;
    wire [11:0] lb_nextrow_raddr;
    reg  [15:0] lb_nextrow_din;
    reg         lb_nextrow_we;
    wire [15:0] lb_nextrow_rdata;

    simple_dual_port_bram #(
        .DATA_WIDTH(16),
        .ADDR_WIDTH(12)
    ) u_line_buffer_nextrow (
        .clk     (clk),
        .we      (lb_nextrow_we),
        .wr_addr (lb_nextrow_waddr),
        .wr_data (lb_nextrow_din),
        .rd_addr (lb_nextrow_raddr),
        .rd_data (lb_nextrow_rdata)
    );

    // =========================================================================
    // FSM Definitions and Registers
    // =========================================================================
    localparam S_IDLE      = 4'd0;
    localparam S_FILL_LB   = 4'd1;
    localparam S_GEN_0     = 4'd2;  // Outputs 00, stores 10
    localparam S_BRAM_WAIT = 4'd3;  // 1-cycle wait for BRAM read latency
    localparam S_GEN_1     = 4'd4;  // Outputs 01, stores 11
    localparam S_DRAIN     = 4'd5;  // Outputs stored 10/11 (odd row)

    reg [3:0]  state;
    reg [3:0]  next_state;  // Target state after BRAM_WAIT
    reg [11:0] x_cnt;
    reg [11:0] y_cnt;
    reg [11:0] lb_nextrow_cnt;
    reg [11:0] in_width;
    reg [11:0] in_height;

    // Registers to hold previous values for bilinear calculations
    reg [15:0] live_reg;
    reg [15:0] buff_reg;

    // =========================================================================
    // Arithmetic (Combinational)
    // =========================================================================
    wire last_line = (y_cnt == ((in_height << 1) - 2));
    reg [15:0] lb_curr_reg; // Holds lb[x_cnt]

    // "live" logic: 
    // In GEN_0, live is the pixel directly below. For last_line, it's the current pixel.
    // In GEN_1, live is the lower-right pixel. For last_line, it's the right neighbor.
    wire [15:0] live = (last_line && state == S_GEN_0) ? lb_curr_reg :
                       (last_line && state == S_GEN_1) ? lb_rdata : 
                       flow_data;

    // 9-bit sign-extended components for safe 2-operand addition
    wire signed [8:0] lb_y9   = {lb_rdata[15], lb_rdata[15:8]};
    wire signed [8:0] lb_x9   = {lb_rdata[7],  lb_rdata[7:0]};
    wire signed [8:0] live_y9 = {live[15],      live[15:8]};
    wire signed [8:0] live_x9 = {live[7],       live[7:0]};
    wire signed [8:0] buff_y9 = {buff_reg[15],  buff_reg[15:8]};
    wire signed [8:0] buff_x9 = {buff_reg[7],   buff_reg[7:0]};
    wire signed [8:0] lreg_y9 = {live_reg[15],  live_reg[15:8]};
    wire signed [8:0] lreg_x9 = {live_reg[7],   live_reg[7:0]};

    // --- GEN_0 Math: 00 and 10 ---
    wire signed [8:0] raw_00_y = lb_y9 + lb_y9;
    wire signed [8:0] raw_00_x = lb_x9 + lb_x9;
    wire signed [8:0] raw_10_y = lb_y9 + live_y9;
    wire signed [8:0] raw_10_x = lb_x9 + live_x9;

    // --- GEN_1 Math: 01 and 11 ---
    // In GEN_1: lb_rdata = right neighbor, buff_reg = current pixel
    //           live_reg = bottom pixel,   live     = bottom-right pixel
    wire signed [10:0] raw_01_y = buff_y9 + lb_y9;
    wire signed [10:0] raw_01_x = buff_x9 + lb_x9;
    wire signed [10:0] sum4_y = buff_y9 + lb_y9 + lreg_y9 + live_y9;
    wire signed [10:0] sum4_x = buff_x9 + lb_x9 + lreg_x9 + live_x9;
    wire signed [10:0] raw_11_y = sum4_y >>> 1;
    wire signed [10:0] raw_11_x = sum4_x >>> 1;

    // --- Last column variants (right neighbor = self) ---
    wire signed [10:0] raw_01_y_last = buff_y9 + buff_y9;
    wire signed [10:0] raw_01_x_last = buff_x9 + buff_x9;
    wire signed [10:0] sum4_y_last = buff_y9 + buff_y9 + lreg_y9 + lreg_y9;
    wire signed [10:0] sum4_x_last = buff_x9 + buff_x9 + lreg_x9 + lreg_x9;
    wire signed [10:0] raw_11_y_last = sum4_y_last >>> 1;
    wire signed [10:0] raw_11_x_last = sum4_x_last >>> 1;

    // =========================================================================
    // Handshake Logic
    // =========================================================================
    wire gen0_ready = (last_line || flow_ready);

    // Read from MRM FIFO during FILL_LB and GEN_0 (not during last line)
    assign flow_rd_en = (state == S_FILL_LB && flow_ready) ||
                        (state == S_GEN_0 && gen0_ready && zoomed_tready && !last_line);

    // Data-ready: indicates zoomed_flow_out is stable and ready for consumption
    assign zoomed_data_ready = (state == S_GEN_0 && gen0_ready) ||
                               (state == S_GEN_1 && (flow_ready || (x_cnt == in_width - 1) || last_line)) ||
                               (state == S_DRAIN);

    // =========================================================================
    // Main State Machine
    // =========================================================================
    // We add S_START_ROW states to prefetch lb[0] and lb[1] before the row starts.
    localparam S_START_ROW_0 = 4'd8;
    localparam S_START_ROW_1 = 4'd9;
    localparam S_START_ROW_2 = 4'd10;

    // Redefine components using lb_curr_reg instead of buff_reg for current pixel
    wire signed [8:0] lb_curr_y9 = {lb_curr_reg[15], lb_curr_reg[15:8]};
    wire signed [8:0] lb_curr_x9 = {lb_curr_reg[7],  lb_curr_reg[7:0]};

    // raw_00 uses lb_curr_reg (which is lb[x_cnt])
    wire signed [10:0] raw_00_y_new = lb_curr_y9 + lb_curr_y9;
    wire signed [10:0] raw_00_x_new = lb_curr_x9 + lb_curr_x9;
    wire signed [10:0] raw_10_y_new = lb_curr_y9 + live_y9;
    wire signed [10:0] raw_10_x_new = lb_curr_x9 + live_x9;

    // raw_01 uses lb_curr_reg (current) and lb_y9 (which is lb[x_cnt+1])
    wire signed [10:0] raw_01_y_new = lb_curr_y9 + lb_y9;
    wire signed [10:0] raw_01_x_new = lb_curr_x9 + lb_x9;
    wire signed [10:0] sum4_y_new = lb_curr_y9 + lb_y9 + lreg_y9 + live_y9;
    wire signed [10:0] sum4_x_new = lb_curr_x9 + lb_x9 + lreg_x9 + live_x9;
    wire signed [10:0] raw_11_y_new = sum4_y_new >>> 1;
    wire signed [10:0] raw_11_x_new = sum4_x_new >>> 1;

    // Last column variants
    wire signed [10:0] raw_01_y_last_new = lb_curr_y9 + lb_curr_y9;
    wire signed [10:0] raw_01_x_last_new = lb_curr_x9 + lb_curr_x9;
    wire signed [10:0] sum4_y_last_new = lb_curr_y9 + lb_curr_y9 + lreg_y9 + lreg_y9;
    wire signed [10:0] sum4_x_last_new = lb_curr_x9 + lb_curr_x9 + lreg_x9 + lreg_x9;
    wire signed [10:0] raw_11_y_last_new = sum4_y_last_new >>> 1;
    wire signed [10:0] raw_11_x_last_new = sum4_x_last_new >>> 1;

    assign lb_nextrow_raddr = 
        (state == S_DRAIN && zoomed_tready) ? x_cnt + 1 :
        (state == S_DRAIN) ? x_cnt :
        12'd0;

    assign zoomed_flow_out = 
        (state == S_GEN_0) ? {shift_clip(raw_00_y_new), shift_clip(raw_00_x_new)} :
        (state == S_GEN_1 && x_cnt == in_width - 1) ? {shift_clip(raw_01_y_last_new), shift_clip(raw_01_x_last_new)} :
        (state == S_GEN_1) ? {shift_clip(raw_01_y_new), shift_clip(raw_01_x_new)} :
        (state == S_DRAIN) ? lb_nextrow_rdata :
        16'd0;

    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            next_state       <= S_IDLE;
            zoom_done        <= 1'b0;
            lb_we            <= 1'b0;
            lb_nextrow_we    <= 1'b0;
            x_cnt            <= 12'd0;
            y_cnt            <= 12'd0;
            lb_nextrow_cnt   <= 12'd0;
            lb_waddr         <= 12'd0;
            lb_raddr         <= 12'd0;
            lb_nextrow_waddr <= 12'd0;
            lb_din           <= 16'd0;
            lb_nextrow_din   <= 16'd0;
            live_reg         <= 16'd0;
            buff_reg         <= 16'd0;
            in_width         <= 12'd0;
            in_height        <= 12'd0;
        end else begin
            // Default: deassert write enables and done pulse
            lb_we         <= 1'b0;
            lb_nextrow_we <= 1'b0;
            zoom_done     <= 1'b0;

            // ── Abort-and-restart: operation_start in a non-IDLE state ─────
            if (operation_start && state != S_IDLE) begin
                state          <= S_FILL_LB;
                x_cnt          <= 12'd0;
                y_cnt          <= 12'd0;
                lb_nextrow_cnt <= 12'd0;
                in_width       <= (IMG_WIDTH) >> curr_layer;
                in_height      <= (IMG_HEIGHT) >> curr_layer;
                lb_we          <= 1'b0;
                lb_nextrow_we  <= 1'b0;
                live_reg       <= 16'd0;
                buff_reg       <= 16'd0;
            end else begin

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (operation_start) begin
                        state          <= S_FILL_LB;
                        x_cnt          <= 12'd0;
                        y_cnt          <= 12'd0;
                        lb_nextrow_cnt <= 12'd0;
                        in_width       <= (IMG_WIDTH) >> curr_layer;
                        in_height      <= (IMG_HEIGHT) >> curr_layer;
                    end
                end

                // ---------------------------------------------------------
                // FILL_LB: Read first row from FIFO into line buffer
                // ---------------------------------------------------------
                S_FILL_LB: begin
                    if (flow_ready) begin
                        lb_we    <= 1'b1;
                        lb_waddr <= x_cnt;
                        lb_din   <= flow_data;

                        if (x_cnt < 10 && curr_layer == 1) begin
                            $display("[ZOOM_FILL_LB %0t] x_cnt=%d flow_data=%h (dx=%d dy=%d)", $time, x_cnt, flow_data, $signed(flow_data[7:0]), $signed(flow_data[15:8]));
                        end

                        if (x_cnt == in_width - 1) begin
                            x_cnt    <= 12'd0;
                            lb_raddr <= 12'd0; // prefetch lb[0]
                            state    <= S_START_ROW_0;
                        end else begin
                            x_cnt <= x_cnt + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // START_ROW pipeline to prefetch lb[0] and lb[1]
                // ---------------------------------------------------------
                S_START_ROW_0: begin
                    state <= S_START_ROW_1; // lb_rdata will be lb[0]
                end

                S_START_ROW_1: begin
                    lb_curr_reg <= lb_rdata; // save lb[0]
                    lb_raddr    <= 12'd1;    // prefetch lb[1]
                    state       <= S_START_ROW_2;
                end

                S_START_ROW_2: begin
                    x_cnt <= 12'd0;
                    state <= S_GEN_0;        // lb_rdata will be lb[1]
                end

                // ---------------------------------------------------------
                // GEN_0: Output 00 pixel, store 10 pixel in nextrow buffer
                // ---------------------------------------------------------
                S_GEN_0: begin
                    if (gen0_ready && zoomed_tready) begin
                        // 1. Output 00 pixel (combinational)

                        // 2. Store 10 pixel in nextrow buffer (shifted & clipped)
                        lb_nextrow_we    <= 1'b1;
                        lb_nextrow_waddr <= lb_nextrow_cnt;
                        lb_nextrow_din   <= {shift_clip(raw_10_y_new), shift_clip(raw_10_x_new)};
                        lb_nextrow_cnt   <= lb_nextrow_cnt + 1;

                        // 3. Overwrite line buffer with live data (for next row)
                        lb_we    <= 1'b1;
                        lb_waddr <= x_cnt;
                        lb_din   <= live;

                        // 4. Save current live for GEN_1
                        live_reg <= live;

                        // 5. Go directly to GEN_1 (no BRAM wait needed!)
                        state <= S_GEN_1;
                    end
                end

                // ---------------------------------------------------------
                // BRAM_WAIT: 1-cycle wait for BRAM read latency.
                // No output produced. Transitions to next_state.
                // ---------------------------------------------------------
                S_BRAM_WAIT: begin
                    state <= next_state;
                    // For transition to DRAIN: also handle zoom_done
                    if (next_state == S_IDLE) begin
                        zoom_done <= 1'b1;
                    end
                end

                // ---------------------------------------------------------
                // GEN_1: Output 01 pixel, store 11 pixel in nextrow buffer
                // ---------------------------------------------------------
                S_GEN_1: begin
                    if ((flow_ready || (x_cnt == in_width - 1) || last_line) && zoomed_tready) begin
                        // Write 11 value to nextrow buffer
                        lb_nextrow_we    <= 1'b1;
                        lb_nextrow_waddr <= lb_nextrow_cnt;

                        // if (last_line && x_cnt < 15) begin
                        //    $display("[ZOOM_DEBUG_LAST] S_GEN_1 x=%d, lb_curr_x9=%d, lb_x9=%d, raw_01_x_new=%d, out=%d, ram_rd=%d, ram_curr=%d, in_width=%d, y_cnt=%d", 
                        //             x_cnt, lb_curr_x9, lb_x9, raw_01_x_new, shift_clip(raw_01_x_new), lb_rdata, lb_curr_reg, in_width, y_cnt);
                        // end

                        if (x_cnt == in_width - 1) begin
                            // === Last column: right neighbor = self ===
                            lb_nextrow_din   <= {shift_clip(raw_11_y_last_new), shift_clip(raw_11_x_last_new)};

                            // Prepare for drain phase
                            x_cnt            <= 12'd0;
                            lb_nextrow_cnt   <= 12'd0;

                            // Go directly to DRAIN
                            state <= S_DRAIN;
                        end else begin
                            // === Normal column ===
                            lb_nextrow_din   <= {shift_clip(raw_11_y_new), shift_clip(raw_11_x_new)};

                            // Advance line buffer pointers
                            lb_curr_reg    <= lb_rdata;    // old right neighbor becomes new current
                            lb_raddr       <= x_cnt + 12'd2; // prefetch next right neighbor

                            x_cnt          <= x_cnt + 1;
                            lb_nextrow_cnt <= lb_nextrow_cnt + 1;

                            // Go directly to GEN_0
                            state <= S_GEN_0;
                        end
                    end
                end

                // ---------------------------------------------------------
                // DRAIN: Output stored 10/11 pixels from nextrow buffer
                // During the last 3 entries, we overlap the line buffer
                // prefetch for the next row pair to eliminate the 3-cycle
                // START_ROW gap that would desynchronize CBW and zoom_in.
                // ---------------------------------------------------------
                S_DRAIN: begin
                    if (zoomed_tready) begin
                        // Output stored data (combinational via lb_nextrow_rdata)

                        if (x_cnt == (in_width << 1) - 1) begin
                            // Last entry in drain — finished this row pair
                            x_cnt          <= 12'd0;
                            lb_nextrow_cnt <= 12'd0;

                            if (last_line) begin
                                state      <= S_BRAM_WAIT;
                                next_state <= S_IDLE;
                                zoom_done  <= 1'b1;
                            end else begin
                                // Prefetch completed during previous drain cycles.
                                // lb_curr_reg = lb[0] (saved at x_cnt=2w-3)
                                // lb_rdata = lb[1] (BRAM read initiated at x_cnt=2w-3,
                                //   data valid at x_cnt=2w-1 after 2-cycle latency)
                                // Go directly to GEN_0, skip START_ROW entirely.
                                state      <= S_GEN_0;
                                y_cnt      <= y_cnt + 2;
                            end
                        end else begin
                            x_cnt <= x_cnt + 1;

                            // Overlap line buffer prefetch with drain.
                            // Synchronous BRAM + non-blocking assignments = 2-cycle
                            // read latency: set addr at cycle N, data valid at cycle N+2.
                            //
                            // Timeline (all gated by zoomed_tready):
                            //   x_cnt=2w-5: lb_raddr <= 0      (initiate lb[0] read)
                            //   x_cnt=2w-4: (wait - BRAM reading mem[0])
                            //   x_cnt=2w-3: lb_rdata = lb[0].  Save lb_curr_reg <= lb_rdata.
                            //               lb_raddr <= 1       (initiate lb[1] read)
                            //   x_cnt=2w-2: (wait - BRAM reading mem[1])
                            //   x_cnt=2w-1: lb_rdata = lb[1].  Transition to GEN_0.
                            if (!last_line) begin
                                if (x_cnt == (in_width << 1) - 12'd5) begin
                                    lb_raddr <= 12'd0;  // Initiate read of lb[0]
                                end
                                if (x_cnt == (in_width << 1) - 12'd3) begin
                                    lb_curr_reg <= lb_rdata;  // lb[0] now valid (2 cycles after addr set)
                                    lb_raddr    <= 12'd1;     // Initiate read of lb[1]
                                end
                            end
                        end
                    end
                end
            endcase
        end
    end
    end  

endmodule