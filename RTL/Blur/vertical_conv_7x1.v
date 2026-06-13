// ============================================================================
// Vertical 7x1 Convolution - Centered with Top Border Reflection
// ============================================================================
// Suppresses output for first 3 input rows (fill phase).
// Applies BORDER_REFLECT_101 for top border taps.
//
// Interface:
//   Input:  Simple wires (in_data, in_valid, in_last) — from line buffers
//   Output: Simple wires (out_data, out_valid, out_last) — to horizontal conv
// ============================================================================

module vertical_conv_7x1 (
    input  wire        clk,
    input  wire        rst_n,
    // Simple wire input from line buffer bank
    input  wire [55:0] in_data,
    input  wire        in_valid,
    input  wire        in_last,
    // Simple wire output to horizontal convolution
    output reg  [20:0] out_data,
    output reg         out_valid,
    output reg         out_last
);

    localparam [9:0] C0 = 10'd528;
    localparam [9:0] C1 = 10'd584;
    localparam [9:0] C2 = 10'd620;
    localparam [9:0] C3 = 10'd632;

    // Row counter
    reg [9:0] row_cnt;
    always @(posedge clk) begin
        if (!rst_n)
            row_cnt <= 10'd0;
        else if (in_valid && in_last)
            row_cnt <= row_cnt + 10'd1;
    end

    // Raw taps from line buffers
    wire [7:0] raw0 = in_data[ 7: 0];
    wire [7:0] raw1 = in_data[15: 8];
    wire [7:0] raw2 = in_data[23:16];
    wire [7:0] raw3 = in_data[31:24];
    wire [7:0] raw4 = in_data[39:32];
    wire [7:0] raw5 = in_data[47:40];
    wire [7:0] raw6 = in_data[55:48];

    // Reflected taps for top border
    // At input row r, output is for centered row r-3.
    // tap[k] = row(r-k). Invalid when r < k. Reflect: row(k-r).
    // row(k-r) maps to tap[2r-k] when 2r-k >= 0.
    wire [7:0] tap0 = raw0;
    wire [7:0] tap1 = raw1;
    wire [7:0] tap2 = raw2;
    wire [7:0] tap3 = raw3;
    // tap4: invalid when row<4. Reflect to tap[2r-4]
    wire [7:0] tap4 = (row_cnt >= 4) ? raw4 :
                       (row_cnt == 3) ? raw2 : raw0;
    // tap5: invalid when row<5. Reflect to tap[2r-5]
    wire [7:0] tap5 = (row_cnt >= 5) ? raw5 :
                       (row_cnt == 4) ? raw3 :
                       (row_cnt == 3) ? raw1 : raw0;
    // tap6: invalid when row<6. Reflect to tap[2r-6]
    wire [7:0] tap6 = (row_cnt >= 6) ? raw6 :
                       (row_cnt == 5) ? raw4 :
                       (row_cnt == 4) ? raw2 :
                       (row_cnt == 3) ? raw0 : raw0;

    // Symmetric pre-add and MAC
    wire [8:0] sym0 = {1'b0, tap0} + {1'b0, tap6};
    wire [8:0] sym1 = {1'b0, tap1} + {1'b0, tap5};
    wire [8:0] sym2 = {1'b0, tap2} + {1'b0, tap4};
    wire [20:0] conv_result = (C0 * sym0) + (C1 * sym1) + (C2 * sym2) + (C3 * tap3);

    // Suppress output for first 3 rows (fill phase)
    wire output_valid = in_valid && (row_cnt >= 3);

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_data  <= 21'd0;
            out_last  <= 1'b0;
        end else begin
            out_valid <= output_valid;
            out_data  <= conv_result;
            out_last  <= in_last;
        end
    end

endmodule
