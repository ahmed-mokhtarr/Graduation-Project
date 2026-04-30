module zoom_in #(
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        clk,
    input  wire        rst_n,

    // Interface with FSM
    input  wire [2:0]  curr_layer,
    input  wire        operation_start,
    output reg         zoom_done,

    // Interface with MRM flow FIFO
    input  wire [31:0] flow_data,
    input  wire        flow_ready,
    output wire        flow_rd_en,

    // Interface with Coefficient BRAM Window mapper (AXI-Stream like)
    output reg  [31:0] zoomed_flow_out,
    output reg         zoomed_tvalid,
    input  wire        zoomed_tready
);
    // -------------------------------------------------------------------------
    // Instantiated Memory 1:Simple Dual Port BRAM (Line Buffer)
    // -------------------------------------------------------------------------
    // Stores the previous row. Max depth needed is IMG_WIDTH / 2.
    // Address width of 12 covers up to 4096, which is plenty for 1280/2 = 640.
    
    reg  [11:0] lb_waddr;
    reg  [11:0] lb_raddr;
    reg  [31:0] lb_din;
    reg         lb_we;
    wire [31:0] lb_rdata; // Changed to wire, driven by BRAM module

    simple_dual_port_bram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(12) 
    ) u_line_buffer (
        .clk     (clk),
        .we      (lb_we),
        .wr_addr (lb_waddr),
        .wr_data (lb_din),
        .rd_addr (lb_raddr),
        .rd_data (lb_rdata)
    );

    // -------------------------------------------------------------------------
    // Instantiated Memory 2: 
    // -------------------------------------------------------------------------


    reg  [11:0] lb_nextrow_waddr;
    reg  [11:0] lb_nextrow_raddr;
    reg  [31:0] lb_nextrow_din;
    reg         lb_nextrow_we;
    wire [31:0] lb_nextrow_rdata;

    simple_dual_port_bram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(12) 
    ) u_line_buffer_nextrow (
        .clk     (clk),
        .we      (lb_nextrow_we),
        .wr_addr (lb_nextrow_waddr),
        .wr_data (lb_nextrow_din),
        .rd_addr (lb_nextrow_raddr),
        .rd_data (lb_nextrow_rdata)
    );


    // -------------------------------------------------------------------------
    // FSM Definitions and Registers
    // -------------------------------------------------------------------------
    localparam S_IDLE     = 3'd0;
    localparam S_FILL_LB  = 3'd1;
    localparam S_GEN_0    = 3'd2; // Generates 00 and 10
    localparam S_GEN_1    = 3'd3; // Generates 01 and 11
    localparam S_DRAIN    = 3'd4;
    localparam S_WAIT_HANDSHAKE = 3'd5;
    
    reg [2:0]  state;
    reg [2:0]  next_state;
    reg [11:0] x_cnt;
    reg [11:0] y_cnt;
    reg [11:0] lb_nextrow_cnt;
    reg [11:0] in_width;
    reg [11:0] in_height;
    reg [11:0] lb_nextrow_width;


    // Registers to hold previous values for bilinear calculations
    reg [31:0] live_reg;
    reg [31:0] buff_reg;


    // -------------------------------------------------------------------------
    // Arithmetic Calculations (Combinational)
    // -------------------------------------------------------------------------
    wire last_line = (y_cnt == in_height - 1);
    wire [31:0] live = last_line ? lb_rdata : flow_data;

    // // S_GEN_0 Math
    wire signed [15:0] out_00_dx = lb_rdata[15:0] <<< 1; // Scaled by 2
    wire signed [15:0] out_00_dy = lb_rdata[31:16] <<< 1;
    wire signed [16:0] sum_10_dx = $signed(lb_rdata[15:0]) + $signed(live[15:0]); 
    wire signed [16:0] sum_10_dy = $signed(lb_rdata[31:16]) + $signed(live[31:16]);

    // // S_GEN_1 Math
    wire signed [16:0] sum_01_dx = $signed(lb_rdata[15:0]) + $signed(buff_reg[15:0]);
    wire signed [16:0] sum_01_dy = $signed(lb_rdata[31:16]) + $signed(buff_reg[31:16]);
    wire signed [17:0] sum_11_dx = $signed(buff_reg[15:0]) + $signed(live_reg[15:0]) + $signed(lb_rdata[15:0]) + $signed(live[15:0]);
    wire signed [17:0] sum_11_dy = $signed(buff_reg[31:16]) + $signed(live_reg[31:16]) + $signed(lb_rdata[31:16]) + $signed(live[31:16]);
    
    wire signed [16:0] sum_01_dx_last_col = $signed(buff_reg[15:0]) + $signed(buff_reg[15:0]);
    wire signed [16:0] sum_01_dy_last_col = $signed(buff_reg[31:16]) + $signed(buff_reg[31:16]);
    wire signed [17:0] sum_11_dx_last_col = $signed(buff_reg[15:0]) + $signed(live_reg[15:0]) + $signed(buff_reg[15:0]) + $signed(live_reg[15:0]);
    wire signed [17:0] sum_11_dy_last_col = $signed(buff_reg[31:16]) + $signed(live_reg[31:16]) + $signed(buff_reg[31:16]) + $signed(live_reg[31:16]);

    // -------------------------------------------------------------------------
    // FSM Handshake Logic 
    // -------------------------------------------------------------------------
    wire gen0_ready  = (last_line || flow_ready);

    // Continuous read request to MRM FIFO
    assign flow_rd_en = (state == S_FILL_LB && flow_ready) || 
                        (state == S_GEN_0 && gen0_ready && !last_line);
                   

    // -------------------------------------------------------------------------
    // Main State Machine
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            zoom_done       <= 1'b0;
            zoomed_tvalid   <= 1'b0;
            zoomed_flow_out <= 32'd0;
            lb_we           <= 1'b0;
            lb_nextrow_we    <= 1'b0;
            x_cnt           <= 12'd0;
            y_cnt           <= 12'd0;
            lb_nextrow_cnt  <= 12'd0;
            
            // Explicitly clear BRAM interface inputs on reset
            lb_waddr        <= 12'd0;
            lb_raddr        <= 12'd0;
            lb_nextrow_waddr <= 12'd0;
            lb_nextrow_raddr <= 12'd0;
            lb_din          <= 32'd0;
            // fifo_din        <= 32'd0;
        end else begin
            // Default pulse clear
            lb_we      <= 1'b0;
            lb_nextrow_we <= 1'b0;
            zoom_done  <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (operation_start) begin
                        state     <= S_FILL_LB;
                        x_cnt     <= 12'd0;
                        y_cnt     <= 12'd0;
                        lb_nextrow_cnt <= 12'd0;
                        in_width  <= (IMG_WIDTH  / 2) >> curr_layer;
                        in_height <= (IMG_HEIGHT / 2) >> curr_layer;
                        lb_nextrow_width <= (IMG_WIDTH) >> curr_layer;
                    end
                end

                S_FILL_LB: begin
                    lb_raddr <= 12'd0; // Prefetch for GEN_0
                    if (flow_ready) begin
                        lb_we    <= 1'b1;
                        lb_waddr <= x_cnt;
                        lb_din   <= flow_data;
                        
                        if (x_cnt == in_width - 1) begin
                            x_cnt    <= 12'd0;
                            
                            state    <= S_GEN_0;
                        end else begin
                            x_cnt <= x_cnt + 1;
                        end
                    end
                end

                S_GEN_0: begin
                    if (gen0_ready) begin
                        // 1. Output the 00 pixel
                        zoomed_tvalid   <= 1'b1;
                        zoomed_flow_out <= {out_00_dy, out_00_dx};
                        
                        // 2. Save the 10 pixel into the FIFO
                        lb_nextrow_we    <= 1'b1; //buggy?
                        lb_nextrow_waddr <= lb_nextrow_cnt;
                        lb_nextrow_din   <= {sum_10_dy[15:0], sum_10_dx[15:0]};
                        lb_nextrow_cnt   <= lb_nextrow_cnt + 1;


                        // 3. Overwrite line buffer with new row
                        lb_we    <= 1'b1;
                        lb_waddr <= x_cnt;
                        lb_din   <= live;
                    
                        lb_raddr <= x_cnt + 1;
                        

                        // 4. Register current inputs to form 'prev' in next phase
                        live_reg  <= live;
                        buff_reg  <= lb_rdata;


                        state <= S_WAIT_HANDSHAKE;
                        next_state <= S_GEN_1; 

                    end
                end 

                S_WAIT_HANDSHAKE: begin
                    if (zoomed_tready && zoomed_tvalid) begin
                        zoomed_tvalid <= 1'b0; // Clear valid after handshake
                        state <= next_state;
                        if (next_state == S_DRAIN) begin
                        lb_nextrow_raddr <= lb_nextrow_cnt + 1; // Start reading from the beginning of next row buffer for drain phase
                        // lb_nextrow_raddr <= 12'd0;
                        end
                        if (last_line && (next_state == S_IDLE)) begin
                                zoom_done <= 1'b1;
                                y_cnt    <= 11'd0;
                                next_state <= S_IDLE;                                
                        end 
                    end
                    
                end


                S_GEN_1: begin
                    if (flow_ready || (x_cnt == in_width - 1) || last_line) begin
                        // 1. Output the 01 pixel
                        zoomed_tvalid   <= 1'b1;
                        // zoomed_flow_out <= {sum_01_dy[15:0], sum_01_dx[15:0]};

                       
                        lb_nextrow_we    <= 1'b1;
                        lb_nextrow_waddr <= lb_nextrow_cnt;
                       
                        lb_nextrow_cnt   <= lb_nextrow_cnt + 1;
                        state <= S_WAIT_HANDSHAKE;

                        // 4. Pre-fetch BRAM index ahead for the NEXT cycle's S_GEN_0
                        // lb_raddr <= x_cnt + 1; // redundant?

                        if (x_cnt == in_width - 1) begin
                            x_cnt <= 12'd0;
                            zoomed_flow_out <= {sum_01_dy_last_col[15:0], sum_01_dx_last_col[15:0]};
                            lb_nextrow_din   <= {sum_11_dy_last_col[16:1], sum_11_dx_last_col[16:1]};
                            
                            next_state <= S_DRAIN;
                            lb_nextrow_cnt <= 12'd0; // Reset for drain phase
                            lb_nextrow_raddr <= 12'd0; // Start reading from the beginning of next row buffer
                        end else begin
                            x_cnt <= x_cnt + 1;
                            zoomed_flow_out <= {sum_01_dy[15:0], sum_01_dx[15:0]};
                            lb_nextrow_din   <= {sum_11_dy[16:1], sum_11_dx[16:1]};
                            
                            next_state <= S_GEN_0;
                        end
                    end
                end

                S_DRAIN: begin

                        // 1. Pop next_row_fifo 10 & 11 data to Output
         
                        zoomed_flow_out <= lb_nextrow_rdata;
                        zoomed_tvalid   <= 1'b1;

                        state     <= S_WAIT_HANDSHAKE;

                        // 2. We loop `in_width * 2` times since FSM pushed exactly that many entries. 
                        if (x_cnt == (in_width << 1) - 1) begin
                            x_cnt    <= 12'd0;
                            // y_cnt    <= y_cnt + 1;
                            lb_raddr <= 12'd0; // Prep for the next row loop
                            lb_nextrow_cnt <= 12'd0; // Reset for next row
                            
                            if (last_line) begin

                                y_cnt    <= y_cnt;
                                // state     <= S_WAIT_HANDSHAKE;
                                next_state <= S_IDLE;                                
                            end else begin
                                // state     <= S_WAIT_HANDSHAKE;
                                next_state <= S_GEN_0;
                                y_cnt    <= y_cnt + 1;
                            end
                        end else begin
                            x_cnt <= x_cnt + 1;
                            next_state <= S_DRAIN;
                            lb_nextrow_raddr <= lb_nextrow_cnt + 1;
                            lb_nextrow_cnt <= lb_nextrow_cnt + 1;
                        end

                end
            endcase
        end
    end

endmodule