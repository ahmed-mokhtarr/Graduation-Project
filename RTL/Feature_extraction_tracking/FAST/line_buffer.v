module line_buffer #(
    parameter DATA_WIDTH = 8,
    parameter LINE_WIDTH = 1280
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // ── Write side ────────────────────────────────────────────────────────
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  din_valid,

    // ── Read side (oldest / displaced sample) ────────────────────────────
    output reg  [DATA_WIDTH-1:0] dout,
    output reg                   dout_valid
);

    localparam ADDR_W = $clog2(LINE_WIDTH);

    // ── single-port RAM ──────────────────────
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:LINE_WIDTH-1];

    // ── Write / read pointer ──────────────────
    reg [ADDR_W-1:0] ptr;

    // ── Full flag: set once the pointer has wrapped ─────────────────
    reg full;

    always @(posedge clk) begin
        if (din_valid)
            mem[ptr] <= din; 
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr        <= {ADDR_W{1'b0}};
            full       <= 1'b0;
            dout       <= {DATA_WIDTH{1'b0}};
            dout_valid <= 1'b0;
        end else begin
            dout_valid <= 1'b0;      

            if (din_valid) begin
                // ── Read displaced (oldest) value first ────────────────
                dout       <= mem[ptr];
                dout_valid <= full;      

                // ── Advance pointer ────────────────────────────────────
                if (ptr == LINE_WIDTH - 1) begin
                    ptr  <= {ADDR_W{1'b0}};
                    full <= 1'b1;    
                end else begin
                    ptr  <= ptr + 1'b1;
                end
            end
        end
    end

endmodule