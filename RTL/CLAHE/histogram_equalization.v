module histogram_equalization 
(
    input   wire              clk,
    input   wire              rst_n,

    input   wire              clip_ready,     // trigger signal   

    // BRAM2 PORT A (Write)
    output reg     [3:0]     tile_idx,
    output reg     [7:0]     wr_bram_addr,
    output reg     [7:0]     wr_bram_data, 
    output reg               wr_bram_en,

    // BRAM1 PORT B (Read)
    output wire     [11:0]     rd_bram_addr,
    input  wire     [15:0]     rd_bram_data,

    output reg                cdf_ready,
    output reg                cdf_mode
);

reg  [8:0]   tile_bin_cnt; 
reg  [15:0]  acc_sum;
reg  [23:0]  multiply_result;  // = acc_sum * cdf_scale_factor (16 * 9 = 25 bits)
wire [7:0]  cdf_result;       // final result to be written
assign cdf_result = multiply_result[23:16]; // equivalent to shift right by 16 to reverse the shift left by 16 (2^16).

assign rd_bram_addr = {tile_idx, tile_bin_cnt[7:0]};

localparam [8:0] cdf_scale_factor = 9'd291;  // ceil(255 * 2^16 / 57600)

localparam  [1:0]   idle  = 2'b00,
                    read_clip_and_cdf = 2'b01,  // address for read and compute the cdf and write it to bram2.
                    next_tile = 2'b10,  // to reinitialize the counters
                    done = 2'b11;  // cdf_ready = 1

reg  [2:0]  current_state , next_state;

always @(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
      current_state <= idle;
    else 
      current_state <= next_state;
  end


always@(*)
 begin
   next_state = current_state;
   case(current_state)
   idle:
      begin
        if(clip_ready)
         begin
          next_state = read_clip_and_cdf;   
         end

      end

   read_clip_and_cdf:
      begin
         if(tile_bin_cnt == 9'd258)
          begin
           next_state = next_tile;
          end
       end

   next_tile:
      begin
        if(tile_idx == 15)
         next_state = done;
        else 
         next_state = read_clip_and_cdf;
      end

   done:
      begin
        next_state = idle;
      end

   default:
      begin
        next_state = idle;
      end

   endcase
 end  


always @(posedge clk or negedge rst_n)
 begin
   if(!rst_n) 
    begin
      tile_idx <= 4'b0;
      tile_bin_cnt <= 9'b0;
      cdf_ready <= 1'b0;
      //rd_bram_addr <= 12'b0;
      wr_bram_addr <= 8'b0;
      wr_bram_data <= 8'b0;
      wr_bram_en <= 1'b0;
      acc_sum <= 16'b0;
      multiply_result <= 24'b0;
    end

   else
    begin
      case(current_state)
      idle:
         begin
            tile_idx <= 4'b0;
            tile_bin_cnt <= 9'b0;
            cdf_ready <= 1'b0;
            //rd_bram_addr <= 12'b0;
            wr_bram_addr <= 8'b0;
            wr_bram_data <= 8'b0;
            wr_bram_en <= 1'b0;
            acc_sum <= 16'b0;
            multiply_result <= 24'b0;
         
         end

      read_clip_and_cdf:
         begin
            if(tile_bin_cnt == 9'b0) // no data valid yet
             begin
               //rd_bram_addr <= {tile_idx, tile_bin_cnt[7:0]};
               tile_bin_cnt <= tile_bin_cnt + 1;
             end  

            else if (tile_bin_cnt == 9'd1) // data valid but now write yet
             begin
               //rd_bram_addr <= {tile_idx, tile_bin_cnt[7:0]};
               acc_sum <= rd_bram_data;
               tile_bin_cnt <= tile_bin_cnt + 1;            
             end  
            else if (tile_bin_cnt == 9'd2)  // multiplication
             begin
               //rd_bram_addr <= {tile_idx, tile_bin_cnt[7:0]};
               acc_sum <= acc_sum + rd_bram_data;
               multiply_result <= acc_sum * cdf_scale_factor; 
               tile_bin_cnt <= tile_bin_cnt + 1;
             end   
            else if(tile_bin_cnt < 256) // start write
             begin
               //rd_bram_addr <= {tile_idx, tile_bin_cnt[7:0]};
               acc_sum <= acc_sum + rd_bram_data;
               multiply_result <= acc_sum * cdf_scale_factor;
               wr_bram_addr <= tile_bin_cnt[7:0] - 2'd3;
               wr_bram_data <= cdf_result;
               wr_bram_en <= 1'b1;
               tile_bin_cnt <= tile_bin_cnt + 1; 
             end    
            else if(tile_bin_cnt == 256) // no read address. just read data and sum and multiply and write.
             begin
               acc_sum <= acc_sum + rd_bram_data;
               multiply_result <= acc_sum * cdf_scale_factor;
               wr_bram_addr <= tile_bin_cnt[7:0] - 2'd3;
               wr_bram_data <= cdf_result;
               wr_bram_en <= 1'b1;
               tile_bin_cnt <= tile_bin_cnt + 1; 
             end    
            else if(tile_bin_cnt == 257) // no sum. just multiply and write
             begin
               multiply_result <= acc_sum * cdf_scale_factor;
               wr_bram_addr <= tile_bin_cnt[7:0] - 2'd3;
               wr_bram_data <= cdf_result;
               wr_bram_en <= 1'b1;
               tile_bin_cnt <= tile_bin_cnt + 1; 
             end    
            else if(tile_bin_cnt == 258) // no multiplication. just write
             begin
               wr_bram_addr <= tile_bin_cnt[7:0] - 2'd3;
               wr_bram_data <= cdf_result;
               wr_bram_en <= 1'b1;
               tile_bin_cnt <= 9'b0;
             end    
             

         end

      next_tile:
         begin
          if(tile_idx < 15)
          begin
           tile_idx <= tile_idx + 4'b0001;
          end 
          tile_bin_cnt <= 9'b0;
          //rd_bram_addr <= 12'b0;
          wr_bram_addr <= 8'b0;
          wr_bram_data <= 8'b0;
          wr_bram_en <= 1'b0;
          acc_sum <= 16'b0;
          multiply_result <= 24'b0;
         end

      done:
         begin
          cdf_ready <= 1'b1;
         end

      default:
         begin
          tile_idx <= 4'b0;
          tile_bin_cnt <= 9'b0;
          cdf_ready <= 1'b0;
          //rd_bram_addr <= 12'b0;
          wr_bram_addr <= 8'b0;
          wr_bram_data <= 8'b0;
          wr_bram_en <= 1'b0;
          acc_sum <= 16'b0;
          multiply_result <= 24'b0;
         end

      endcase 
      end
   end

   always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) begin
            cdf_mode <= 1'b0;
        end else if (clip_ready) begin
            cdf_mode <= 1'b1; // Turn ON cdf control
        end else if (cdf_ready) begin
            cdf_mode <= 1'b0; // Turn OFF cdf control
        end
    end

   // I will do the bram linking and everything in the top module.

endmodule