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
    localparam IDLE           = 2'b00;
    localparam WRITE_ADDR     = 2'b01;
    localparam READ_DATA      = 2'b10;
    localparam CHECK_FINISH   = 2'b11;

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
    reg [1:0]  state;
    reg [31:0] target_beats; // size may be changed
    reg [31:0] beats_read;
    reg [31:0] current_address;
    
    wire [31:0] remaining_beats = target_beats - beats_read;
    assign rready = (state == READ_DATA) && ~fifo_full;
    assign fifo_en = (state == READ_DATA) && rvalid && rready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            read_done       <= 1'b0;
            // fifo_en         <= 1'b0;
            araddr          <= 32'd0;
            arlen           <= 8'd0;
            arvalid         <= 1'b0;
            // rready          <= 1'b0;
            target_beats    <= 32'd0;
            beats_read      <= 32'd0;
            current_address <= 32'd0;
        end else begin
            read_done <= 1'b0;
            // fifo_en   <= 1'b0;

            case (state)
                IDLE: begin
                    if (start_read) begin
                        target_beats    <= total_beats_wire;
                        current_address <= curr_addr;
                        beats_read      <= 0;
                        
                        // Setup the first burst
                        arlen   <= (total_beats_wire > 256) ? 8'd255 : (total_beats_wire[7:0] - 8'd1);
                        araddr  <= curr_addr;
                        arvalid <= 1'b1;
                        state   <= WRITE_ADDR;
                    end
                end

                WRITE_ADDR: begin
                    // Wait for the Smart Connect to accept the address
                    if (arvalid && arready) begin
                        arvalid <= 1'b0;
                        state   <= READ_DATA;
                    end
                end

                READ_DATA: begin
                    // rready <= ~fifo_full; // Accept data if FIFO has space
                    
                    if (rvalid && rready) begin
                        // fifo_en    <= 1'b1;
                        beats_read <= beats_read + 1;
                        
                        if (rlast) begin
                            // Advance address for the next potential burst
                            current_address <= current_address + ((arlen + 1) * BYTES_PER_BEAT);
                            state           <= CHECK_FINISH;
                        end
                    end
                end

                CHECK_FINISH: begin
                    if (beats_read >= target_beats) begin
                        // Entire layer is complete
                        read_done <= 1'b1;
                        state     <= IDLE;
                    end else begin
                        // Setup the next AXI burst transaction
                        arlen   <= (remaining_beats > 256) ? 8'd255 : (remaining_beats[7:0] - 8'd1);
                        araddr  <= current_address;
                        arvalid <= 1'b1;
                        state   <= WRITE_ADDR;
                    end
                end
            endcase
        end
    end
endmodule