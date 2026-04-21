module histogram_generation 
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
    output wire    [11:0]     rd_bram_addr,
    input  wire    [15:0]     rd_bram_data,

    output reg                hist_ready
);




localparam TOTAL_PIXELS = 921600;
reg  [19:0] pixel_count;

// registered address and valid
reg valid_reg;
reg [11:0] addr_reg;

// Forwarding to handle the case of same pixels after each other (100 100)
reg fwd_valid;
reg [11:0] fwd_addr;
reg [15:0] fwd_wr_data;
// Second stage of forwarding to handle the case of (100 101 100)
reg fwd_valid_2;
reg [11:0] fwd_addr_2;
reg [15:0] fwd_wr_data_2;


// Checking case 1
wire conflict_flag_1;

// Checking case 2
wire conflict_flag_2;



wire [15:0]  rd_data;
wire [11:0]  curr_addr; 

assign conflict_flag_1 = fwd_valid && (fwd_addr == addr_reg);
assign conflict_flag_2 = fwd_valid_2 && (fwd_addr_2 == addr_reg);

assign curr_addr = {tile_idx, pixel_in};
assign rd_data = (conflict_flag_1) ? fwd_wr_data :
                 (conflict_flag_2) ? fwd_wr_data_2 : 
                 rd_bram_data;
                 
assign rd_bram_addr = curr_addr;



// preparing reading
always @(posedge clk or negedge rst_n)
 begin
  if(!rst_n)
   begin
    valid_reg <= 1'b0;
    addr_reg <= 12'b0;
   end 
  else
   begin
    valid_reg <= pixel_v;
    addr_reg <= curr_addr;
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
        fwd_valid_2 <= 0;     // Reset Stage 2
        fwd_addr_2 <= 0;      // Reset Stage 2
        fwd_wr_data_2 <= 0;   // Reset Stage 2
        pixel_count <= 0;
     end   
    else if(valid_reg) 
     begin
        // Shift Stage 1 into Stage 2
        fwd_valid_2   <= fwd_valid;
        fwd_addr_2    <= fwd_addr;
        fwd_wr_data_2 <= fwd_wr_data;

        if(pixel_count == 0) 
         begin
            wr_bram_en <= 1'b1;
            wr_bram_addr <= addr_reg;
            wr_bram_data <= 1'b1;
    
            fwd_valid <= 1'b1;
            fwd_addr <= addr_reg;
            fwd_wr_data <= 1'b1;

            pixel_count <= 1'b1;
         end 
        else  
          begin
            wr_bram_en <= 1'b1;
            wr_bram_addr <= addr_reg;
            wr_bram_data <= rd_data + 1'b1;
    
            fwd_valid <= 1'b1;
            fwd_addr <= addr_reg;
            fwd_wr_data <= rd_data + 1'b1;
            pixel_count <= pixel_count + 1'b1;
          end 
    end 
     else 
          begin
            wr_bram_en <= 1'b0;
            fwd_valid <= 1'b0;
            fwd_valid_2 <= 1'b0; // Clear Stage 2 on invalid
            
            if (pixel_count == TOTAL_PIXELS) 
             begin
                pixel_count <= 0; 
             end
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