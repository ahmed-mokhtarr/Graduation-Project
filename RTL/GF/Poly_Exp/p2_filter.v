// ============================================================
// p2_filter — Symmetric 11-tap second-derivative filter
//
// Separable Farneback p2 kernel (× 2^16, rounded):
//   [155, 692, 1610, 1272, -1753, -3950, -1753, 1272, 1610, 692, 155]
//
// Architecture: 3-stage pipeline
//   Stage 1 — pre-add symmetric pairs (reduces 11 taps → 5 sums + 1 center)
//   Stage 2 — multiply each sum/center by its coefficient
//   Stage 3 — adder tree (6 terms) → output register
//
// Bit-width derivation (all localparams, only IN_WIDTH is a parameter):
//   COEFF_W  = 13          widest coefficient (|-3950| < 2^12 → fits in 13-bit signed)
//   SUM_W    = IN_WIDTH+1  pre-add of two IN_WIDTH values grows by 1 bit
//   PROD_W   = SUM_W+COEFF_W
//   OUT_WIDTH= PROD_W+3    ceil(log2(6 terms)) = 3 guard bits for adder tree
// ============================================================
module p2_filter #(          // ← FIXED: was incorrectly named p1_filter
    parameter IN_WIDTH = 9
)(
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          valid_in,
    input  wire signed [IN_WIDTH*11-1:0] data_in_packed,

    output reg                           valid_out,
    // OUT_WIDTH = (IN_WIDTH+1+13)+3 = IN_WIDTH+17
    output reg  signed [IN_WIDTH+16:0]   data_out
);

    // --------------------------------------------------------
    // Derived bit-width localparams
    // --------------------------------------------------------
    localparam COEFF_W   = 13;              // widest p2 coefficient
    localparam SUM_W     = IN_WIDTH + 1;    // pre-add grows by 1 bit
    localparam PROD_W    = SUM_W + COEFF_W; // = IN_WIDTH + 14
    localparam OUT_WIDTH = PROD_W + 3;      // = IN_WIDTH + 17  (guard bits for 6-term tree)

    // --------------------------------------------------------
    // Filter Coefficients (float × 2^16, rounded)
    // Symmetric: h[k] = h[10-k]
    // --------------------------------------------------------
    localparam signed [12:0] C0 = -13'sd3950;  // center (tap 5)
    localparam signed [11:0] C1 = -12'sd1753;  // taps 4 & 6
    localparam signed [11:0] C2 =  12'sd1272;  // taps 3 & 7
    localparam signed [11:0] C3 =  12'sd1610;  // taps 2 & 8
    localparam signed [10:0] C4 =  11'sd692;   // taps 1 & 9
    localparam signed [8:0]  C5 =   9'sd155;   // taps 0 & 10 (outermost)

    // --------------------------------------------------------
    // Unpack input (index 0 = newest/rightmost, 10 = oldest/leftmost)
    // --------------------------------------------------------
    wire signed [IN_WIDTH-1:0] d [0:10];
    genvar i;
    generate
        for (i = 0; i < 11; i = i + 1) begin : unpack
            assign d[i] = data_in_packed[(i+1)*IN_WIDTH-1 : i*IN_WIDTH];
        end
    endgenerate

    // --------------------------------------------------------
    // Stage 1 — Pre-add symmetric pairs (registered)
    // --------------------------------------------------------
    reg signed [SUM_W-1:0]    s1_sum [0:4];
    reg signed [IN_WIDTH-1:0] s1_center;
    reg                       s1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_sum[0] <= 0; s1_sum[1] <= 0; s1_sum[2] <= 0;
            s1_sum[3] <= 0; s1_sum[4] <= 0;
            s1_center <= 0; s1_valid  <= 0;
        end else begin
            s1_valid <= valid_in;
            if (valid_in) begin
                s1_sum[0] <= d[4] + d[6];   // pair for C1
                s1_sum[1] <= d[3] + d[7];   // pair for C2
                s1_sum[2] <= d[2] + d[8];   // pair for C3
                s1_sum[3] <= d[1] + d[9];   // pair for C4
                s1_sum[4] <= d[0] + d[10];  // pair for C5
                s1_center <= d[5];           // center tap
            end
        end
    end

    // --------------------------------------------------------
    // Stage 2 — Multiply (registered)
    // --------------------------------------------------------
    reg signed [PROD_W-1:0] s2_prod [0:5];
    reg                     s2_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_prod[0] <= 0; s2_prod[1] <= 0; s2_prod[2] <= 0;
            s2_prod[3] <= 0; s2_prod[4] <= 0; s2_prod[5] <= 0;
            s2_valid <= 0;
        end else begin
            s2_valid <= s1_valid;
            if (s1_valid) begin
                s2_prod[0] <= s1_center * C0;
                s2_prod[1] <= s1_sum[0] * C1;
                s2_prod[2] <= s1_sum[1] * C2;
                s2_prod[3] <= s1_sum[2] * C3;
                s2_prod[4] <= s1_sum[3] * C4;
                s2_prod[5] <= s1_sum[4] * C5;
            end
        end
    end

    // --------------------------------------------------------
    // Stage 3 — Adder tree + output register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= 0;
            valid_out <= 0;
        end else begin
            valid_out <= s2_valid;
            if (s2_valid)
                data_out <= s2_prod[0] + s2_prod[1] + s2_prod[2] +
                            s2_prod[3] + s2_prod[4] + s2_prod[5];
        end
    end

endmodule