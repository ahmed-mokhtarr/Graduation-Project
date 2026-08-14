module bram_clear_controller
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear_start,     // pulse to begin clearing

    output reg  [11:0] wr_addr,         // to histogram BRAM write port
    output wire [15:0] wr_data,         // always 0
    output reg         wr_en,           // write enable
    output reg         clear_done,      // single-cycle pulse when complete
    output reg         clear_mode       // high during clearing (MUX select)
);

assign wr_data = 16'b0;

localparam IDLE     = 1'b0,
           CLEARING = 1'b1;

reg state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= IDLE;
        wr_addr    <= 12'b0;
        wr_en      <= 1'b0;
        clear_done <= 1'b0;
        clear_mode <= 1'b0;
    end else begin
        clear_done <= 1'b0;  // default: single-cycle pulse

        case (state)
            IDLE: begin
                wr_en      <= 1'b0;
                clear_mode <= 1'b0;
                if (clear_start) begin
                    state      <= CLEARING;
                    wr_addr    <= 12'b0;
                    wr_en      <= 1'b1;
                    clear_mode <= 1'b1;
                end
            end

            CLEARING: begin
                if (wr_addr == 12'd4095) begin
                    wr_en      <= 1'b0;
                    clear_done <= 1'b1;
                    clear_mode <= 1'b0;
                    state      <= IDLE;
                end else begin
                    wr_addr <= wr_addr + 12'd1;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
