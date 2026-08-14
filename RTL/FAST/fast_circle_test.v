module fast_circle_test #(
    parameter DATA_WIDTH = 8,
    parameter THRESHOLD  = 35,
    parameter N_CONSEC   = 9
)(
    input  wire [DATA_WIDTH-1:0]    Ip,
    input  wire [16*DATA_WIDTH-1:0] circle,  
    output wire                     is_corner  
);

    localparam D = DATA_WIDTH;

    // ── Threshold bounds ───────────
    wire [8:0] upper_raw = {1'b0, Ip} + THRESHOLD[8:0];
    wire [8:0] lower_raw = {1'b0, Ip} - THRESHOLD[8:0];

    wire [7:0] upper = (upper_raw > 9'd255) ? 8'hFF : upper_raw[7:0];
    wire [7:0] lower = (lower_raw[8])       ? 8'h00 : lower_raw[7:0];

    // ── Extract individual circle pixels into local wires ─────────────────
    wire [D-1:0] px [0:15];
    genvar k;
    generate
        for (k = 0; k < 16; k = k + 1) begin : PX_EXTRACT
            assign px[k] = circle[k*D +: D];
        end
    endgenerate

    // ── Classify doubled ring ──────────
    wire bright [0:31];
    wire dark   [0:31];
    generate
        for (k = 0; k < 32; k = k + 1) begin : CLASSIFY
            assign bright[k] = (px[(k < 16) ? k : k - 16] > upper);
            assign dark[k]   = (px[(k < 16) ? k : k - 16] < lower);
        end
    endgenerate

    // ── Run-length check ───────────────────
    reg found_bright, found_dark;
    integer i, j;
    reg [4:0] run_b, run_d;

    always @(*) begin
        found_bright = 1'b0;
        found_dark   = 1'b0;
        for (i = 0; i < 16; i = i + 1) begin
            run_b = 5'd0;
            run_d = 5'd0;
            for (j = 0; j < N_CONSEC; j = j + 1) begin
                if (bright[i + j]) run_b = run_b + 5'd1;
                if (dark  [i + j]) run_d = run_d + 5'd1;
            end
            if (run_b == N_CONSEC) found_bright = 1'b1;
            if (run_d == N_CONSEC) found_dark   = 1'b1;
        end
    end

    assign is_corner = found_bright | found_dark;

endmodule