module window_shift_reg #(
    parameter DATA_WIDTH = 24,
    parameter WINDOW_SIZE = 11
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   valid_in,
    input  wire signed [DATA_WIDTH-1:0] data_in,
    output wire signed [DATA_WIDTH*WINDOW_SIZE-1:0] window_out_packed
);

    reg signed [DATA_WIDTH-1:0] window_out [0:WINDOW_SIZE-1];
    integer k;

    genvar i;
    generate
        for (i = 0; i < WINDOW_SIZE; i = i + 1) begin : pack_window
            assign window_out_packed[(i+1)*DATA_WIDTH-1 : i*DATA_WIDTH] = window_out[i];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < WINDOW_SIZE; k = k + 1) begin
                window_out[k] <= 0;
            end
        end else begin
            if (valid_in) begin
                window_out[0] <= data_in;
                for (k = 1; k < WINDOW_SIZE; k = k + 1) begin
                    window_out[k] <= window_out[k-1];
                end
            end
        end
    end

endmodule
