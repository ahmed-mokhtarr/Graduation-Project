module frame_sync_fsm #(
    parameter DDR_BASE_A = 32'h1000_0000,
    parameter DDR_BASE_B = 32'h1010_0000
)(
    input  wire        clk,
    input  wire        rst_n,

    // External
    input  wire        frame_start,      // SOF from camera

    // Pipeline status
    input  wire        cdf_ready,        // CDF computation complete

    // BRAM clear
    input  wire        clear_done,       // histogram BRAM cleared
    output reg         clear_start,      // pulse to bram_clear_controller

    // DDR read control
    input  wire        read_frame_done,  // axi_read_master finished (not strictly needed by FSM anymore)
    output reg         read_start,       // pulse to axi_read_master

    // DDR addresses
    output wire [31:0] write_base_addr,
    output wire [31:0] read_base_addr
);

reg frame_bank;

assign write_base_addr = frame_bank ? DDR_BASE_B : DDR_BASE_A;
assign read_base_addr  = frame_bank ? DDR_BASE_A : DDR_BASE_B;

localparam IDLE       = 2'd0,
           WAIT_CDF   = 2'd1,
           CLEAR_BRAM = 2'd2;

reg [1:0] state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= IDLE;
        frame_bank  <= 1'b0;
        clear_start <= 1'b0;
        read_start  <= 1'b0;
    end else begin
        // single-cycle pulses
        clear_start <= 1'b0;
        read_start  <= 1'b0;

        case (state)
            IDLE: begin
                if (frame_start)
                    state <= WAIT_CDF;
            end

            WAIT_CDF: begin
                if (cdf_ready) begin
                    clear_start <= 1'b1;
                    state       <= CLEAR_BRAM;
                end
            end

            CLEAR_BRAM: begin
                if (clear_done) begin
                    frame_bank <= ~frame_bank;
                    // Trigger readback immediately for the frame we just stored
                    read_start <= 1'b1;
                    state      <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule
