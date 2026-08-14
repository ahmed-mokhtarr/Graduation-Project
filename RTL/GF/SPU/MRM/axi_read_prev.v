module axi_read_prev #(
    parameter AXI_DATA_WIDTH  = 64,
    parameter AXI_ADDR_WIDTH  = 32,
    parameter IMG_WIDTH       = 1280,
    parameter IMG_HEIGHT      = 720,
    parameter BYTES_PER_PIXEL = 1
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // ACU Interface
    input  wire [AXI_ADDR_WIDTH-1:0] prev_addr,
    input  wire [2:0]                curr_layer,
    input  wire                      start_read,
    output reg                       read_done,

    // Previous FIFO Interface
    input  wire                      fifo_full,
    output wire [AXI_DATA_WIDTH-1:0] fifo_data,
    output wire                       fifo_en,

    // AXI4 Smart Connect AR Channel
    output reg  [AXI_ADDR_WIDTH-1:0] araddr,
    output reg  [7:0]                arlen,
    output wire [2:0]                arsize,
    output wire [1:0]                arburst,
    output reg                       arvalid,
    input  wire                      arready,

    // AXI4 Smart Connect R Channel
    input  wire [AXI_DATA_WIDTH-1:0] rdata,
    input  wire                      rlast,
    input  wire                      rvalid,
    output wire                       rready
);

    localparam BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
    localparam IDLE           = 3'b000;
    localparam WRITE_ADDR     = 3'b001;
    localparam READ_DATA      = 3'b010;
    localparam CHECK_FINISH   = 3'b011;
    localparam DRAIN_BURST    = 3'b100;

    reg [31:0] total_beats_wire;

    always @(*) begin
        case (curr_layer)
            3'd0:    total_beats_wire = ((IMG_WIDTH)      * (IMG_HEIGHT)      * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            3'd1:    total_beats_wire = ((IMG_WIDTH >> 1) * (IMG_HEIGHT >> 1) * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            3'd2:    total_beats_wire = ((IMG_WIDTH >> 2) * (IMG_HEIGHT >> 2) * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            3'd3:    total_beats_wire = ((IMG_WIDTH >> 3) * (IMG_HEIGHT >> 3) * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            3'd4:    total_beats_wire = ((IMG_WIDTH >> 4) * (IMG_HEIGHT >> 4) * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            default: total_beats_wire = 32'd0;
        endcase
    end

    assign arsize    = 3'b100;
    assign arburst   = 2'b01;
    assign fifo_data = rdata;

    reg [2:0]  state;
    reg [31:0] target_beats;
    reg [31:0] beats_read;
    reg [31:0] current_address;

    reg        restart_pending;
    reg [31:0] pend_target;
    reg [31:0] pend_addr;
    reg [7:0]  pend_arlen;

    wire [31:0] remaining_beats = target_beats - beats_read;
    assign rready  = ((state == READ_DATA) && ~fifo_full) || (state == DRAIN_BURST);
    assign fifo_en = (state == READ_DATA) && rvalid && rready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            read_done       <= 1'b0;
            araddr          <= 32'd0;
            arlen           <= 8'd0;
            arvalid         <= 1'b0;
            target_beats    <= 32'd0;
            beats_read      <= 32'd0;
            current_address <= 32'd0;
            restart_pending <= 1'b0;
            pend_target     <= 32'd0;
            pend_addr       <= 32'd0;
            pend_arlen      <= 8'd0;
        end else begin
            read_done <= 1'b0;

            if (start_read && state != IDLE) begin
                pend_target <= total_beats_wire;
                pend_addr   <= prev_addr;
                pend_arlen  <= (total_beats_wire > 256) ? 8'd255 : (total_beats_wire[7:0] - 8'd1);
                restart_pending <= 1'b1;

                if (state == CHECK_FINISH) begin
                    target_beats    <= total_beats_wire;
                    current_address <= prev_addr;
                    beats_read      <= 32'd0;
                    arlen           <= (total_beats_wire > 256) ? 8'd255 : (total_beats_wire[7:0] - 8'd1);
                    araddr          <= prev_addr;
                    arvalid         <= 1'b1;
                    state           <= WRITE_ADDR;
                    restart_pending <= 1'b0;
                end else if (state == READ_DATA) begin
                    state <= DRAIN_BURST;
                end
            end else begin

            case (state)
                IDLE: begin
                    if (start_read) begin
                        target_beats    <= total_beats_wire;
                        current_address <= prev_addr;
                        beats_read      <= 32'd0;
                        arlen   <= (total_beats_wire > 256) ? 8'd255 : (total_beats_wire[7:0] - 8'd1);
                        araddr  <= prev_addr;
                        arvalid <= 1'b1;
                        state   <= WRITE_ADDR;
                    end
                end

                WRITE_ADDR: begin
                    if (arvalid && arready) begin
                        arvalid <= 1'b0;
                        state <= restart_pending ? DRAIN_BURST : READ_DATA;
                    end
                end

                READ_DATA: begin
                    if (rvalid && rready) begin
                        beats_read <= beats_read + 1;
                        if (rlast) begin
                            current_address <= current_address + ((arlen + 1) * BYTES_PER_BEAT);
                            state           <= CHECK_FINISH;
                        end
                    end
                end

                CHECK_FINISH: begin
                    if (beats_read >= target_beats) begin
                        read_done <= 1'b1;
                        state     <= IDLE;
                    end else begin
                        arlen   <= (remaining_beats > 256) ? 8'd255 : (remaining_beats[7:0] - 8'd1);
                        araddr  <= current_address;
                        arvalid <= 1'b1;
                        state   <= WRITE_ADDR;
                    end
                end

                DRAIN_BURST: begin
                    if (rvalid) begin
                        if (rlast) begin
                            target_beats    <= pend_target;
                            current_address <= pend_addr;
                            beats_read      <= 32'd0;
                            arlen           <= pend_arlen;
                            araddr          <= pend_addr;
                            arvalid         <= 1'b1;
                            state           <= WRITE_ADDR;
                            restart_pending <= 1'b0;
                        end
                    end
                end

                default: state <= IDLE;
            endcase

            end
        end
    end
endmodule