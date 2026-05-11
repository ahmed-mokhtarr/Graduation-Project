// ============================================================
// 15-Tap Box Filter (Adder Tree)
// Bit growth: OUT_WIDTH = IN_WIDTH + 4
// Latency: 4 clock cycles
// ============================================================
module filter_15tap #(
    parameter IN_WIDTH = 32
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          valid_in,
    input  wire signed [IN_WIDTH*15-1:0] data_in_packed,
    output reg                           valid_out,
    output reg  signed [IN_WIDTH+3:0]    data_out
);
    localparam SUM_W = IN_WIDTH + 4;

    // Unpack inputs
    wire signed [IN_WIDTH-1:0] d [0:14];
    genvar i;
    generate
        for (i = 0; i < 15; i = i + 1) begin : unpack
            assign d[i] = data_in_packed[(i+1)*IN_WIDTH-1 : i*IN_WIDTH];
        end
    endgenerate

    // Stage 1: 7 additions, 1 passthrough
    reg signed [IN_WIDTH:0] s1_sum [0:6];
    reg signed [IN_WIDTH-1:0] s1_pass;
    reg s1_valid;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
        end else begin
            s1_valid <= valid_in;
            if (valid_in) begin
                s1_sum[0] <= d[0] + d[1];
                s1_sum[1] <= d[2] + d[3];
                s1_sum[2] <= d[4] + d[5];
                s1_sum[3] <= d[6] + d[7];
                s1_sum[4] <= d[8] + d[9];
                s1_sum[5] <= d[10] + d[11];
                s1_sum[6] <= d[12] + d[13];
                s1_pass   <= d[14];
            end
        end
    end

    // Stage 2: 4 additions
    reg signed [IN_WIDTH+1:0] s2_sum [0:3];
    reg s2_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) s2_valid <= 0;
        else begin
            s2_valid <= s1_valid;
            if (s1_valid) begin
                s2_sum[0] <= s1_sum[0] + s1_sum[1];
                s2_sum[1] <= s1_sum[2] + s1_sum[3];
                s2_sum[2] <= s1_sum[4] + s1_sum[5];
                s2_sum[3] <= s1_sum[6] + s1_pass;
            end
        end
    end

    // Stage 3: 2 additions
    reg signed [IN_WIDTH+2:0] s3_sum [0:1];
    reg s3_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) s3_valid <= 0;
        else begin
            s3_valid <= s2_valid;
            if (s2_valid) begin
                s3_sum[0] <= s2_sum[0] + s2_sum[1];
                s3_sum[1] <= s2_sum[2] + s2_sum[3];
            end
        end
    end

    // Stage 4: Final addition
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            data_out  <= 0;
        end else begin
            valid_out <= s3_valid;
            if (s3_valid) begin
                data_out <= s3_sum[0] + s3_sum[1];
            end
        end
    end
endmodule