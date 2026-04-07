module HISTOGRAM_GENERATION 
(
    input   wire              clk,
    input   wire              rst_n,

    input   wire              pixel_v,         // valid signal
    input   wire   [7:0]      pixel_in,        // data_in
    input   wire   [3:0]      tile_idx,
    // start of frame signal

    
    // BRAM PORT A (Write)
    output reg     [11:0]     wr_bram_addr,
    output reg     [15:0]     wr_bram_data,
    output reg                wr_bram_en,

    // BRAM PORT B (Read)
    output reg     [11:0]     rd_bram_addr,
    input  wire    [15:0]     rd_bram_data,

    output reg                hist_ready,
);


// reg  [15:0]  bram_mem_histo [4095:0];

localparam TOTAL_PIXELS = 921600;
reg  [19:0] pixel_count;

// registered address and valid
reg valid_reg;
reg [11:0] addr_reg;

// Forwarding to handle the case of same pixels after each other
reg fwd_valid;
reg [11:0] fwd_addr;
reg [15:0] fwd_wr_data;

// Checking if same pixels came after each other
wire conflict_flag;



wire rd_data;
wire [11:0]  curr_addr; 

assign conflict_flag = fwd_valid && (fwd_addr == addr_reg);
assign curr_addr = {tile_idx, pixel_in};
assign rd_data = (conflict_flag) ? fwd_wr_data : rd_bram_data;



// preparing reading
always @(posedge clk or negedge rst_n)
 begin
  if(!rst_n)
   begin
    valid_reg <= 1'b0;
    addr_reg <= 12'b0;
    rd_bram_addr <= 12'b0;
   end 
  else
   begin
    valid_reg <= pixel_v;
    addr_reg <= curr_addr;
    rd_bram_addr <= curr_addr;
   end
 end 



always@(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
     begin
        wr_bram_addr <= 0;
        wr_bram_data <= 0;
        wr_bram_en <= 0;
        fwd_valid <= 0;
        fwd_addr <= 0;
        fwd_wr_data <= 0;
        pixel_count <= 0;
     end   
     else if(valid_reg)
      begin
        wr_bram_en = 1'b1;
        wr_bram_addr = addr_reg;
        wr_bram_data <= rd_data + 1'b1;

        fwd_valid = 1'b1;
        fwd_addr = addr_reg;
        fwd_wr_data = rd_data + 1'b1;

        pixel_count = pixel_count + 1'b1;
      end
      
  end  

  always@(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
     begin
        hist_ready <= 1'b0;
     end   

     else if(pixel_count == TOTAL_PIXELS)
      begin
        hist_ready <= 1'b1;
      end
      else 
       hist_ready <= 1'b0;
  end

endmodule