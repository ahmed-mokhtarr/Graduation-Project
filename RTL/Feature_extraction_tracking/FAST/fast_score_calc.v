module fast_score_calc #(
    parameter DATA_WIDTH  = 8,
    parameter THRESHOLD   = 35,
    parameter SCORE_WIDTH = 12
)(
    input  wire [DATA_WIDTH-1:0]    Ip,
    input  wire [16*DATA_WIDTH-1:0] circle,   
    output wire [SCORE_WIDTH-1:0]   score     
);

    localparam D = DATA_WIDTH;
    localparam SW = SCORE_WIDTH;

    // ── Threshold bounds ──────────────────────────────────────────────────
    wire [8:0] upper_raw = {1'b0, Ip} + THRESHOLD[8:0];
    wire [8:0] lower_raw = {1'b0, Ip} - THRESHOLD[8:0];

    wire [7:0] upper = (upper_raw > 9'd255) ? 8'hFF : upper_raw[7:0];
    wire [7:0] lower = (lower_raw[8])       ? 8'h00 : lower_raw[7:0];

    // ── Extract pixels ────────────────────────────────────────────────────
    wire [D-1:0] px [0:15];
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : PX_EXTRACT
            assign px[i] = circle[i*D +: D];
        end
    endgenerate

    // ── Per-pixel contributions ───────────────────────────────────────────
    wire [SW-1:0] bc [0:15];  
    wire [SW-1:0] dc [0:15];   

    generate
        for (i = 0; i < 16; i = i + 1) begin : CONTRIB
            wire [8:0] diff_b = {1'b0, px[i]} - {1'b0, upper};
            wire [8:0] diff_d = {1'b0, lower}  - {1'b0, px[i]};

            assign bc[i] = (px[i] > upper) ? {{(SW-9){1'b0}}, diff_b} : {SW{1'b0}};
            assign dc[i] = (px[i] < lower) ? {{(SW-9){1'b0}}, diff_d} : {SW{1'b0}};
        end
    endgenerate

    wire [SW-1:0] sum_bright = bc[0]+bc[1]+bc[2]+bc[3]+bc[4]+bc[5]+bc[6]+bc[7]+
                               bc[8]+bc[9]+bc[10]+bc[11]+bc[12]+bc[13]+bc[14]+bc[15];
    wire [SW-1:0] sum_dark   = dc[0]+dc[1]+dc[2]+dc[3]+dc[4]+dc[5]+dc[6]+dc[7]+
                               dc[8]+dc[9]+dc[10]+dc[11]+dc[12]+dc[13]+dc[14]+dc[15];

    assign score = (sum_bright >= sum_dark) ? sum_bright : sum_dark;

endmodule