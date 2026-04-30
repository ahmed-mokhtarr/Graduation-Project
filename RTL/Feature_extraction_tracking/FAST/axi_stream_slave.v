module axi_stream_slave #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    // ── Clock / reset ──────────────────────────────────────────────────────
    input  wire       clk,
    input  wire       rst_n,

    // ── AXI4-Stream slave port ─────────────────────────────────────────────
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,  
    input  wire       s_axis_tlast,    // end-of-line
    input  wire       s_axis_tuser,    // start-of-frame (with first pixel)

    // ── Internal pixel bus ─────────────────────────────────────────────────
    output reg  [7:0] pixel_data,
    output reg        pixel_valid,
    output reg  [$clog2(IMG_WIDTH) -1:0] col_cnt,
    output reg  [$clog2(IMG_HEIGHT)-1:0] row_cnt
);

    assign s_axis_tready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_data  <= 8'd0;
            pixel_valid <= 1'b0;
            col_cnt     <= 0;
            row_cnt     <= 0;
        end else begin
            pixel_valid <= 1'b0;

            if (s_axis_tvalid & s_axis_tready) begin
                pixel_data  <= s_axis_tdata;
                pixel_valid <= 1'b1;

                if (s_axis_tuser) begin
                    col_cnt <= 0;  
                    row_cnt <= 0;
                end 
                else if (s_axis_tlast) begin
                    col_cnt <= 0;
                    if (row_cnt == IMG_HEIGHT - 1)
                        row_cnt <= 0;
                    else
                        row_cnt <= row_cnt + 1;
                end 
                else begin
                    col_cnt <= col_cnt + 1;
                end
            end
        end
    end

endmodule