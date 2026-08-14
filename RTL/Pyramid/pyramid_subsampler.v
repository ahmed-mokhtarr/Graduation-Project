`timescale 1ns / 1ps

module pyramid_subsampler (
    input  wire        clk,
    input  wire        rst_n,

    // AXI-Stream Input (from Blur Module)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser, // Start of Frame
    input  wire        s_axis_tlast, // End of Line

    // Trigger to FSM
    output wire        eof_pulse_out,

    // Interfaces to the 5 Synchronous FIFOs
    output reg  [31:0] L0_data,  // din for fifo
    output reg         L0_valid,
    input  wire        L0_full,

    output reg  [31:0] L1_data,
    output reg         L1_valid,
    input  wire        L1_full,

    output reg  [31:0] L2_data,
    output reg         L2_valid,
    input  wire        L2_full,

    output reg  [31:0] L3_data,
    output reg         L3_valid,
    input  wire        L3_full,

    output reg  [31:0] L4_data,
    output reg         L4_valid,
    input  wire        L4_full
);
 
    localparam MAX_Y = 10'd719;

    reg eof_pulse_reg;
    reg [10:0] x_cnt;
    reg [9:0]  y_cnt;

    // Filter enables
    wire L0_en = 1'b1;                                               
    wire L1_en = (x_cnt[0] == 1'b0)   && (y_cnt[0] == 1'b0);         
    wire L2_en = (x_cnt[1:0] == 2'b00) && (y_cnt[1:0] == 2'b00);     
    wire L3_en = (x_cnt[2:0] == 3'b000) && (y_cnt[2:0] == 3'b000);   
    wire L4_en = (x_cnt[3:0] == 4'b0000) && (y_cnt[3:0] == 4'b0000); 

    // Packing Shift Registers and Counters
    reg [23:0] L0_shift, L1_shift, L2_shift, L3_shift, L4_shift;
    reg [1:0]  L0_cnt, L1_cnt, L2_cnt, L3_cnt, L4_cnt; // for packing the 32 bit.

    assign s_axis_tready = ~(L0_full | L1_full | L2_full | L3_full | L4_full);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt <= 11'd0; y_cnt <= 10'd0;
            L0_valid <= 1'b0;
            L1_valid <= 1'b0; 
            L2_valid <= 1'b0; 
            L3_valid <= 1'b0; 
            L4_valid <= 1'b0;

            L0_data <= 32'd0; 
            L1_data <= 32'd0; 
            L2_data <= 32'd0; 
            L3_data <= 32'd0; 
            L4_data <= 32'd0;

            L0_cnt <= 0; 
            L1_cnt <= 0; 
            L2_cnt <= 0; 
            L3_cnt <= 0; 
            L4_cnt <= 0;

            L0_shift <= 0; 
            L1_shift <= 0; 
            L2_shift <= 0; 
            L3_shift <= 0; 
            L4_shift <= 0;

        end else begin
            // Default pulldowns for write enables
            L0_valid <= 1'b0; 
            L1_valid <= 1'b0; 
            L2_valid <= 1'b0; 
            L3_valid <= 1'b0; 
            L4_valid <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                
                // 1. Coordinates and Alignment Reset
                if (s_axis_tuser) begin
                    x_cnt <= 11'd1; 
                    y_cnt <= 10'd0;
                    // Reset packers on Start of Frame to ensure exact 4-byte alignment
                    L0_cnt <= 0; 
                    L1_cnt <= 0; 
                    L2_cnt <= 0; 
                    L3_cnt <= 0; 
                    L4_cnt <= 0;
                end else if (s_axis_tlast) begin
                    x_cnt <= 11'd0; 
                    y_cnt <= y_cnt + 10'd1;
                end else begin
                    x_cnt <= x_cnt + 11'd1;
                end

                // 2. Data Packing (8-bit to 32-bit Little Endian)
                if (L0_en) begin
                    if (L0_cnt == 0) L0_shift[7:0]   <= s_axis_tdata;
                    if (L0_cnt == 1) L0_shift[15:8]  <= s_axis_tdata;
                    if (L0_cnt == 2) L0_shift[23:16] <= s_axis_tdata;
                    if (L0_cnt == 3) begin
                        L0_data  <= {s_axis_tdata, L0_shift[23:0]};
                        L0_valid <= 1'b1;
                    end
                    L0_cnt <= L0_cnt + 1;
                end

                if (L1_en) begin
                    if (L1_cnt == 0) L1_shift[7:0]   <= s_axis_tdata;
                    if (L1_cnt == 1) L1_shift[15:8]  <= s_axis_tdata;
                    if (L1_cnt == 2) L1_shift[23:16] <= s_axis_tdata;
                    if (L1_cnt == 3) begin 
                        L1_data <= {s_axis_tdata, L1_shift[23:0]}; 
                        L1_valid <= 1'b1; 
                    end
                    L1_cnt <= L1_cnt + 1;
                end

                if (L2_en) begin
                    if (L2_cnt == 0) L2_shift[7:0]   <= s_axis_tdata;
                    if (L2_cnt == 1) L2_shift[15:8]  <= s_axis_tdata;
                    if (L2_cnt == 2) L2_shift[23:16] <= s_axis_tdata;
                    if (L2_cnt == 3) begin 
                        L2_data <= {s_axis_tdata, L2_shift[23:0]}; 
                        L2_valid <= 1'b1; 
                    end
                    L2_cnt <= L2_cnt + 1;
                end

                if (L3_en) begin
                    if (L3_cnt == 0) L3_shift[7:0]   <= s_axis_tdata;
                    if (L3_cnt == 1) L3_shift[15:8]  <= s_axis_tdata;
                    if (L3_cnt == 2) L3_shift[23:16] <= s_axis_tdata;
                    if (L3_cnt == 3) begin 
                        L3_data <= {s_axis_tdata, L3_shift[23:0]}; 
                        L3_valid <= 1'b1; 
                    end
                    L3_cnt <= L3_cnt + 1;
                end

                if (L4_en) begin
                    if (L4_cnt == 0) L4_shift[7:0]   <= s_axis_tdata;
                    if (L4_cnt == 1) L4_shift[15:8]  <= s_axis_tdata;
                    if (L4_cnt == 2) L4_shift[23:16] <= s_axis_tdata;
                    if (L4_cnt == 3) begin 
                        L4_data <= {s_axis_tdata, L4_shift[23:0]}; 
                        L4_valid <= 1'b1; 
                    end
                    L4_cnt <= L4_cnt + 1;
                end
            end
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            eof_pulse_reg <= 1'b0;
        else 
            eof_pulse_reg <= s_axis_tvalid && s_axis_tready && s_axis_tlast && (y_cnt == MAX_Y);
    end
    assign eof_pulse_out = eof_pulse_reg;

endmodule