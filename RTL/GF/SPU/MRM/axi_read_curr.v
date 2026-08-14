module axi_read_curr #(
    parameter AXI_DATA_WIDTH  = 64,
    parameter AXI_ADDR_WIDTH  = 32,
    parameter IMG_WIDTH       = 1280,
    parameter IMG_HEIGHT      = 720,
    parameter BYTES_PER_PIXEL = 1
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // ACU Interface
    input  wire [AXI_ADDR_WIDTH-1:0] curr_addr,
    input  wire [2:0]                curr_layer,
    input  wire                      start_read,
    output reg                       read_done,

    // Current FIFO Interface
    input  wire                      fifo_full,
    output wire [AXI_DATA_WIDTH-1:0] fifo_data,
    output wire                      fifo_en,

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

    // -------------------------------------------------------------------------
    // Local Parameters & Size Calculation
    // -------------------------------------------------------------------------
    localparam BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
    localparam IDLE           = 3'b000;
    localparam WRITE_ADDR     = 3'b001;
    localparam READ_DATA      = 3'b010;
    localparam CHECK_FINISH   = 3'b011;
    localparam DRAIN_BURST    = 3'b100;

    // Calculate total beats for the requested layer
    reg [31:0] total_beats_wire;

    always @(*) begin
        case (curr_layer)
            3'd0:    total_beats_wire = ((IMG_WIDTH)      * (IMG_HEIGHT)      * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            3'd1:    total_beats_wire = ((IMG_WIDTH >> 1) * (IMG_HEIGHT >> 1) * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            3'd2:    total_beats_wire = ((IMG_WIDTH >> 2) * (IMG_HEIGHT >> 2) * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            3'd3:    total_beats_wire = ((IMG_WIDTH >> 3) * (IMG_HEIGHT >> 3) * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            3'd4:    total_beats_wire = ((IMG_WIDTH >> 4) * (IMG_HEIGHT >> 4) * BYTES_PER_PIXEL) / BYTES_PER_BEAT;
            default: total_beats_wire = 32'd0; // Safe default
        endcase
    end

    // AXI specific hardcoded wires (16 bytes per beat = 3'b100, INCR burst = 2'b01)
    assign arsize    = 3'b100; 
    assign arburst   = 2'b01;  
    assign fifo_data = rdata;

    // -------------------------------------------------------------------------
    // FSM & Control Logic
    // -------------------------------------------------------------------------
    reg [2:0]  state;
    reg [31:0] target_beats;
    reg [31:0] beats_read;
    reg [31:0] current_address;

    // Pending restart registers (for abort-and-restart)
    reg        restart_pending;
    reg [31:0] pend_target;
    reg [31:0] pend_addr;
    reg [7:0]  pend_arlen;
    
    wire [31:0] remaining_beats = target_beats - beats_read;

    // rready: accept data in READ_DATA (if FIFO not full) or DRAIN_BURST (always accept to discard)
    assign rready  = ((state == READ_DATA) && ~fifo_full) || (state == DRAIN_BURST);
    // Only write to FIFO during normal READ_DATA, NOT during DRAIN
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

            // ── Abort-and-restart: start_read in a non-IDLE state ──────────
            if (start_read && state != IDLE) begin
                pend_target <= total_beats_wire;
                pend_addr   <= curr_addr;
                pend_arlen  <= (total_beats_wire > 256) ? 8'd255 : (total_beats_wire[7:0] - 8'd1);
                restart_pending <= 1'b1;

                if (state == CHECK_FINISH) begin
                    // No in-flight AXI burst — start new read immediately
                    target_beats    <= total_beats_wire;
                    current_address <= curr_addr;
                    beats_read      <= 32'd0;
                    arlen           <= (total_beats_wire > 256) ? 8'd255 : (total_beats_wire[7:0] - 8'd1);
                    araddr          <= curr_addr;
                    arvalid         <= 1'b1;
                    state           <= WRITE_ADDR;
                    restart_pending <= 1'b0;
                end else if (state == READ_DATA) begin
                    // In-flight burst — drain remaining beats (discard data)
                    state <= DRAIN_BURST;
                end
                // WRITE_ADDR: keep waiting for arready, then FSM below routes to DRAIN
            end else begin

            // ── Normal FSM ─────────────────────────────────────────────────
            case (state)
                IDLE: begin
                    if (start_read) begin
                        target_beats    <= total_beats_wire;
                        current_address <= curr_addr;
                        beats_read      <= 32'd0;
                        arlen   <= (total_beats_wire > 256) ? 8'd255 : (total_beats_wire[7:0] - 8'd1);
                        araddr  <= curr_addr;
                        arvalid <= 1'b1;
                        state   <= WRITE_ADDR;
                    end
                end

                WRITE_ADDR: begin
                    if (arvalid && arready) begin
                        arvalid <= 1'b0;
                        // If a restart is pending, drain the burst we just initiated
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
                    // Accept and discard AXI beats until rlast
                    if (rvalid) begin  // rready is always 1 in DRAIN_BURST
                        if (rlast) begin
                            // Burst fully drained — start the new read
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

            end // else (not start_read abort)
        end
    end
endmodule