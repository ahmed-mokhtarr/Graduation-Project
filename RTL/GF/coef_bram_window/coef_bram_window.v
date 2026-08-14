module coef_bram_window #(
    parameter DLIMIT = 12
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // Config
    input  wire [2:0]             layer_config,
    
    // Input Stream (from coef_gen curr channel)
    input  wire                   valid_in,
    input  wire signed [14:0]     r2_curr,
    input  wire signed [16:0]     r3_curr,
    input  wire signed [13:0]     r4_curr,
    input  wire signed [16:0]     r5_curr,
    input  wire signed [14:0]     r6_curr,
    
    // Flow upper (d vector) input from zoom-in module
    // Arrives in sync with the r_curr at (x_in, y_in)
    input  wire signed [7:0]      flow_upper_x,
    input  wire signed [7:0]      flow_upper_y,
    
    // Backpressure to upstream (coef_gen / zoom-in)
    // Directly passes through — coef_bram_window never stalls
    // (tready is always high while accepting data)
    output wire                   tready,
    
    // Output Stream (to update_top)
    output reg                    valid_out,
    output reg  signed [14:0]     r2_shifted,
    output reg  signed [16:0]     r3_shifted,
    output reg  signed [13:0]     r4_shifted,
    output reg  signed [16:0]     r5_shifted,
    output reg  signed [14:0]     r6_shifted
);

    localparam DATA_WIDTH = 78; // 15 + 17 + 14 + 17 + 15
    wire [DATA_WIDTH-1:0] r_curr_packed = {r6_curr, r5_curr, r4_curr, r3_curr, r2_curr};

    // --- Row BRAM count: need 2*DLIMIT+2 rows accessible simultaneously ---
    localparam NUM_BRAMS   = 2 * DLIMIT + 2;      // 26 for DLIMIT=12, 32 for DLIMIT=15
    localparam BRAM_IDX_W  = $clog2(NUM_BRAMS);   // 5 for NUM_BRAMS=26

    // --- Delay RAM: stores flow_upper for (DLIMIT+1)*max_width pipeline delay ---
    localparam DELAY_DEPTH  = (DLIMIT + 2) * 1280; // 17920 for DLIMIT=12
    localparam DELAY_ADDR_W = $clog2(DELAY_DEPTH);  // 15 for 17920

    // --------------------------------------------------------
    // Dynamic Width/Height Decoding
    // --------------------------------------------------------
    reg [10:0] width;
    reg [10:0] height;

    always @(*) begin
        case (layer_config)
            3'd0: begin width = 11'd1280; height = 11'd720; end
            3'd1: begin width = 11'd640;  height = 11'd360; end
            3'd2: begin width = 11'd320;  height = 11'd180; end
            3'd3: begin width = 11'd160;  height = 11'd90;  end
            3'd4: begin width = 11'd80;   height = 11'd45;  end
            default: begin width = 11'd1280; height = 11'd720; end
        endcase
    end

    // --------------------------------------------------------
    // FSM States
    // --------------------------------------------------------
    localparam IDLE     = 2'd0;
    localparam ACTIVE   = 2'd1;
    localparam DRAINING = 2'd2;
    localparam DONE     = 2'd3;

    // FSM
    // --------------------------------------------------------
    reg [1:0] state;
    reg       last_pixel_received;
    reg [2:0] h_pad_cnt;

    // tready: accept data during IDLE and ACTIVE
    assign tready = (state == IDLE) || (state == ACTIVE);

    // We can only pump if we're not waiting out the horizontal blanking gap
    wire in_h_pad = (h_pad_cnt != 3'd0);
    wire pump = (state == DRAINING) ? (!in_h_pad) : (valid_in && tready);

    // --------------------------------------------------------
    // Input Tracking
    // --------------------------------------------------------
    reg [10:0] x_in;
    reg [10:0] y_in;
    reg [BRAM_IDX_W-1:0] wr_bram_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_in <= 11'd0;
            y_in <= 11'd0;
            wr_bram_idx <= {BRAM_IDX_W{1'b0}};
            last_pixel_received <= 1'b0;
        end else if (valid_in && tready) begin
            last_pixel_received <= 1'b0;
            if (x_in == width - 11'd1) begin
                x_in <= 11'd0;
                if (y_in == height - 11'd1) begin
                    y_in <= 11'd0;
                    wr_bram_idx <= {BRAM_IDX_W{1'b0}};
                    last_pixel_received <= 1'b1;
                end else begin
                    y_in <= y_in + 11'd1;
                    // Explicit wrap at NUM_BRAMS (not power-of-2 overflow)
                    wr_bram_idx <= (wr_bram_idx == NUM_BRAMS[BRAM_IDX_W-1:0] - 1)
                                   ? {BRAM_IDX_W{1'b0}}
                                   : wr_bram_idx + 1'b1;
                end
            end else begin
                x_in <= x_in + 11'd1;
            end
        end else begin
            last_pixel_received <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // Output Tracking & Delay Logic
    // --------------------------------------------------------
    reg [10:0] x_out;
    reg [10:0] y_out;
    reg out_started;
    
    // --------------------------------------------------------
    // Pump logic:
    // ACTIVE state: slave directly to valid_in (1:1 with input, keeps delay_ram
    //               pointers and BRAM read/write synchronized).
    // DRAINING state: free-running to flush out remaining pixels, gated by h_pad.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_pad_cnt <= 3'd0;
        end else begin
            if (in_h_pad) begin
                h_pad_cnt <= h_pad_cnt - 3'd1;
            end else if (pump && out_started && x_out == width - 11'd1) begin
                // End of output row — start 7-cycle blanking gap
                h_pad_cnt <= 3'd7;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_out <= 11'd0;
            y_out <= 11'd0;
            out_started <= 1'b0;
        end else if (pump) begin
            if (!out_started) begin
                // Start output after DLIMIT+1 rows have been buffered
                if (y_in == DLIMIT[10:0] + 11'd1 && x_in == 11'd0) begin
                    out_started <= 1'b1;
                    x_out <= 11'd0;
                    y_out <= 11'd0;
                end
            end else begin
                if (x_out == width - 11'd1) begin
                    x_out <= 11'd0;
                    if (y_out == height - 11'd1) begin
                        y_out <= 11'd0;
                        out_started <= 1'b0; // Reset for next frame
                    end else begin
                        y_out <= y_out + 11'd1;
                    end
                end else begin
                    x_out <= x_out + 11'd1;
                end
            end
        end
    end

    // --------------------------------------------------------
    // Forward declarations for pipeline stage 2 signals
    // (needed by FSM below)
    // --------------------------------------------------------
    reg        out_started_q2;
    reg        valid_in_q2;       // tracks ACTIVE-phase pipeline valid
    reg        valid_in_q2_drain; // tracks DRAINING-phase pipeline valid
    wire       pipeline_valid = valid_in_q2 || valid_in_q2_drain;

    // --------------------------------------------------------
    // FSM: Controls ACTIVE vs DRAINING phases
    // --------------------------------------------------------
    // Total output pixels to produce
    reg [20:0] output_count;
    wire [20:0] total_pixels = {10'd0, width} * {10'd0, height};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            output_count <= 21'd0;
        end else begin
            case (state)
                IDLE: begin
                    output_count <= 21'd0;
                    if (valid_in)
                        state <= ACTIVE;
                end

                ACTIVE: begin
                    // Count outputs produced
                    if (pipeline_valid && out_started_q2)
                        output_count <= output_count + 21'd1;

                    // When last input pixel is received, switch to draining
                    if (last_pixel_received)
                        state <= DRAINING;
                end

                DRAINING: begin
                    // Count outputs produced during drain
                    if (pipeline_valid && out_started_q2)
                        output_count <= output_count + 21'd1;

                    // Done when all outputs have been emitted
                    if (output_count >= total_pixels)
                        state <= DONE;
                end

                DONE: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // --------------------------------------------------------
    // Delay RAM for flow_upper (reduced depth based on DLIMIT)
    // --------------------------------------------------------
    reg [15:0] delay_ram [0:DELAY_DEPTH-1];
    reg [DELAY_ADDR_W-1:0] delay_wr_ptr;
    reg [DELAY_ADDR_W-1:0] delay_rd_ptr;

    always @(posedge clk) begin
        if (valid_in && tready) begin
            delay_ram[delay_wr_ptr] <= {flow_upper_x, flow_upper_y};
        end
    end

    reg [15:0] delayed_flow;
    wire signed [7:0] d_x_out;
    wire signed [7:0] d_y_out;

    always @(posedge clk) begin
        if (pump)
            delayed_flow <= delay_ram[delay_rd_ptr];
    end
    
    assign d_x_out = delayed_flow[15:8];
    assign d_y_out = delayed_flow[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delay_wr_ptr <= {DELAY_ADDR_W{1'b0}};
            delay_rd_ptr <= {DELAY_ADDR_W{1'b0}};
        end else begin
            if (valid_in && tready)
                delay_wr_ptr <= (delay_wr_ptr == DELAY_DEPTH[DELAY_ADDR_W-1:0] - 1)
                                ? {DELAY_ADDR_W{1'b0}}
                                : delay_wr_ptr + 1;
            // Read pointer advances whenever we are pumping and outputting
            if (pump && out_started)
                delay_rd_ptr <= (delay_rd_ptr == DELAY_DEPTH[DELAY_ADDR_W-1:0] - 1)
                                ? {DELAY_ADDR_W{1'b0}}
                                : delay_rd_ptr + 1;
        end
    end

    // --------------------------------------------------------
    // Pipeline stage 1: align with delay_ram read latency
    // --------------------------------------------------------
    reg [10:0] x_out_q;
    reg [10:0] y_out_q;
    reg        out_started_q;
    reg        pump_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_out_q <= 11'd0;
            y_out_q <= 11'd0;
            out_started_q <= 1'b0;
            pump_q <= 1'b0;
        end else begin
            if (pump) begin
                x_out_q <= x_out;
                y_out_q <= y_out;
                out_started_q <= out_started;
            end
            pump_q <= pump;
        end
    end

    // --------------------------------------------------------
    // Read Address Calculation & Clipping
    // --------------------------------------------------------
    wire signed [11:0] raw_req_x = $signed({1'b0, x_out_q}) + d_x_out;
    wire signed [11:0] raw_req_y = $signed({1'b0, y_out_q}) + d_y_out;

    wire [10:0] req_x = (raw_req_x < 0) ? 11'd0 :
                        (raw_req_x >= $signed({1'b0, width})) ? width - 11'd1 :
                        raw_req_x[10:0];

    wire [10:0] req_y = (raw_req_y < 0) ? 11'd0 :
                        (raw_req_y >= $signed({1'b0, height})) ? height - 11'd1 :
                        raw_req_y[10:0];

    // --------------------------------------------------------
    // Pipeline stage 2: align with BRAM read latency
    // --------------------------------------------------------
    reg [10:0] req_y_q;
    // out_started_q2, valid_in_q2, valid_in_q2_drain declared above (before FSM)
    
    reg signed [7:0] d_x_out_q;
    reg signed [7:0] d_y_out_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_y_q <= 11'd0;
            out_started_q2 <= 1'b0;
            valid_in_q2 <= 1'b0;
            valid_in_q2_drain <= 1'b0;
            d_x_out_q <= 8'd0;
            d_y_out_q <= 8'd0;
        end else begin
            if (pump_q) begin
                req_y_q <= req_y;
                out_started_q2 <= out_started_q;
                d_x_out_q <= d_x_out;
                d_y_out_q <= d_y_out;
            end
            valid_in_q2 <= pump_q && (state == ACTIVE || state == IDLE);
            valid_in_q2_drain <= pump_q && (state == DRAINING);
        end
    end

    // --------------------------------------------------------
    // BRAM Instantiations (NUM_BRAMS = 2*DLIMIT+2 row BRAMs)
    // --------------------------------------------------------
    wire [DATA_WIDTH-1:0] bram_rd_data [0:NUM_BRAMS-1];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_BRAMS; gi = gi + 1) begin : gen_bram
            simple_dual_port_bram #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(11)
            ) bram_inst (
                .clk      (clk),
                .we       (valid_in && tready && (wr_bram_idx == gi)),
                .wr_addr  (x_in),
                .wr_data  (r_curr_packed),
                .rd_addr  (req_x), 
                .rd_data  (bram_rd_data[gi])
            );
        end
    endgenerate

    // --------------------------------------------------------
    // Modular BRAM Index for Reading (req_y % NUM_BRAMS)
    // Row y is stored in BRAM (y mod NUM_BRAMS).
    // For non-power-of-2 NUM_BRAMS, use modulo operator
    // (Vivado synthesizes this efficiently for constant divisors).
    // --------------------------------------------------------
    reg [BRAM_IDX_W-1:0] rd_bram_idx;
    always @(posedge clk) begin
        if (pump_q) begin
            rd_bram_idx <= req_y % NUM_BRAMS;
        end
    end

    // --------------------------------------------------------
    // Output Multiplexing and Final Registers
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            r2_shifted <= 15'd0;
            r3_shifted <= 17'd0;
            r4_shifted <= 14'd0;
            r5_shifted <= 17'd0;
            r6_shifted <= 15'd0;
        end else begin
            if (pipeline_valid) begin
                valid_out <= out_started_q2;
                r6_shifted <= bram_rd_data[rd_bram_idx][77:63];
                r5_shifted <= bram_rd_data[rd_bram_idx][62:46];
                r4_shifted <= bram_rd_data[rd_bram_idx][45:32];
                r3_shifted <= bram_rd_data[rd_bram_idx][31:15];
                r2_shifted <= bram_rd_data[rd_bram_idx][14:0];
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
