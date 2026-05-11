module line_buffer (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control
    input  wire        valid_in,
    input  wire [2:0]  layer_config,
    
    // Data
    input  wire [7:0]  pixel_in,
    output wire [7:0]  pixel_out
);

    // --------------------------------------------------------
    // Dynamic Width Decoding
    // --------------------------------------------------------
    reg [10:0] current_width;

    always@ (*) 
     begin
        case (layer_config)
            3'd0: current_width = 11'd1280; // Layer 0
            3'd1: current_width = 11'd640;  // Layer 1
            3'd2: current_width = 11'd320;  // Layer 2
            3'd3: current_width = 11'd160;  // Layer 3
            3'd4: current_width = 11'd80;   // Layer 4
            default: current_width = 11'd1280;
        endcase
     end

    // --------------------------------------------------------
    // Read/Write Pointer Logic
    // --------------------------------------------------------
    reg [10:0] ptr;
    wire  [10:0] wr_ptr;
    reg  [10:0] rd_ptr;

    // assign rd_ptr = (valid_in) ? ptr + 11'd1 : ptr;

    always@(*)
     begin
        if(valid_in && ptr < current_width - 1'b1)
         rd_ptr = ptr + 11'd1;
        else if(valid_in && ptr == current_width - 1'b1) 
         rd_ptr = 11'd0;
        else
         rd_ptr = ptr; 
     end   

    assign wr_ptr = ptr;


    always @(posedge clk or negedge rst_n) 
     begin
        if (!rst_n) begin
            ptr <= 11'd0;
        end else if (valid_in) begin
            if (ptr == current_width - 1'b1) begin
                ptr <= 11'd0; // Wrap around for the next row
            end else begin
                ptr <= ptr + 1'b1;
            end
        end
     end



    // --------------------------------------------------------
    // BRAM Instantiation
    // --------------------------------------------------------
    simple_dual_port_bram #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(11) // 2^11 = 2048
    ) bram_inst (
        .clk      (clk),
        .we       (valid_in),
        .wr_addr  (wr_ptr),
        .wr_data  (pixel_in),
        .rd_addr  (rd_ptr),
        .rd_data  (pixel_out)
    );

endmodule