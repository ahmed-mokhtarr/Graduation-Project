// ============================================================
// p1_filter — Anti-symmetric 11-tap first-derivative filter
//
// Separable Farneback p1 kernel (× 2^16, rounded):
//   [-150, -888, -3155, -6389, -6222, 0, 6222, 6389, 3155, 888, 150]
//
// Architecture: 3-stage pipeline
//   Stage 1 — pre-subtract anti-symmetric pairs (diff = upper - lower)
//              Center tap is zero → skipped
//   Stage 2 — multiply each diff by its (positive) coefficient
//   Stage 3 — adder tree (5 terms) → output register
//
// Bit-width derivation (all localparams, only IN_WIDTH is a parameter):
//   COEFF_W  = 14          widest coefficient (6389 < 2^13 → fits in 14-bit signed)
//   DIFF_W   = IN_WIDTH+1  pre-subtract of two IN_WIDTH values grows by 1 bit
//   PROD_W   = DIFF_W+COEFF_W
//   OUT_WIDTH= PROD_W+3    ceil(log2(5 terms)) = 3 guard bits for adder tree
// ============================================================
module p1_filter #(
    parameter IN_WIDTH = 9
)(
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          valid_in,
    input  wire signed [IN_WIDTH*11-1:0] data_in_packed,

    output reg                           valid_out,
    // OUT_WIDTH = (IN_WIDTH+1+14)+3 = IN_WIDTH+18
    output reg  signed [IN_WIDTH+17:0]   data_out
);

    // --------------------------------------------------------
    // Derived bit-width localparams
    // --------------------------------------------------------
    localparam COEFF_W   = 14;              // widest p1 coefficient
    localparam DIFF_W    = IN_WIDTH + 1;    // pre-subtract grows by 1 bit
    localparam PROD_W    = DIFF_W + COEFF_W; // = IN_WIDTH + 15
    localparam OUT_WIDTH = PROD_W + 3;       // = IN_WIDTH + 18  (guard bits for 5-term tree)

    // --------------------------------------------------------
    // Filter Coefficients (float × 2^16, rounded)
    // Anti-symmetric: h[k] = -h[10-k], h[5] = 0
    // Stored as POSITIVE upper-half magnitudes.
    // --------------------------------------------------------
    localparam signed [13:0] C1 = 14'sd6222;  // taps 4 & 6
    localparam signed [13:0] C2 = 14'sd6389;  // taps 3 & 7
    localparam signed [12:0] C3 = 13'sd3155;  // taps 2 & 8
    localparam signed [10:0] C4 = 11'sd888;   // taps 1 & 9
    localparam signed [8:0]  C5 =  9'sd150;   // taps 0 & 10 (outermost)

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
    // Stage 1 — Pre-subtract anti-symmetric pairs (registered)
    //   diff[k] = d[upper] - d[lower]
    //   because h[upper] is positive, h[lower] is negative
    // --------------------------------------------------------
    reg signed [DIFF_W-1:0] s1_diff [0:4];
    reg                     s1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_diff[0] <= 0; s1_diff[1] <= 0; s1_diff[2] <= 0;
            s1_diff[3] <= 0; s1_diff[4] <= 0;
            s1_valid   <= 0;
        end else begin
            s1_valid <= valid_in;
            if (valid_in) begin
                s1_diff[0] <= d[4] - d[6];   // pair for C1
                s1_diff[1] <= d[3] - d[7];   // pair for C2
                s1_diff[2] <= d[2] - d[8];   // pair for C3
                s1_diff[3] <= d[1] - d[9];   // pair for C4
                s1_diff[4] <= d[0] - d[10];  // pair for C5
            end
        end
    end

    // --------------------------------------------------------
    // Stage 2 — Multiply (registered); center tap (=0) skipped
    // --------------------------------------------------------
    reg signed [PROD_W-1:0] s2_prod [0:4];
    reg                     s2_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_prod[0] <= 0; s2_prod[1] <= 0; s2_prod[2] <= 0;
            s2_prod[3] <= 0; s2_prod[4] <= 0;
            s2_valid   <= 0;
        end else begin
            s2_valid <= s1_valid;
            if (s1_valid) begin
                s2_prod[0] <= s1_diff[0] * C1;
                s2_prod[1] <= s1_diff[1] * C2;
                s2_prod[2] <= s1_diff[2] * C3;
                s2_prod[3] <= s1_diff[3] * C4;
                s2_prod[4] <= s1_diff[4] * C5;
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
                            s2_prod[3] + s2_prod[4];
        end
    end

endmodule