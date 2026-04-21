module clipping_redistribution 
(
    input   wire              clk,
    input   wire              rst_n,

    input   wire              hist_ready,         // trigger signal

    // BRAM PORT A (Write)
    output reg     [11:0]     wr_bram_addr,
    output reg     [15:0]     wr_bram_data,  // 16 bit but could be reduced as the max written value in this module should be 675 (clip_limit) so to be only 10 bit.
    output reg                wr_bram_en,

    // BRAM PORT B (Read)
    output wire     [11:0]     rd_bram_addr,
    input  wire     [15:0]     rd_bram_data,

    output reg                clip_ready,
    output reg                clipping_mode
);

reg [3:0] tile_cnt;
reg [8:0] tile_bin_cnt; 

reg [15:0] excess_total;
localparam CLIP_LIMIT = 675;

wire [7:0] excess_per_bin;
wire [7:0] excess_per_bin_reminder;

assign excess_per_bin = excess_total[15:8];
assign excess_per_bin_reminder = excess_total[7:0];

reg [8:0] remainder_acc; // 9 bits to catch the overflow carry
wire [8:0] next_acc;

// Constantly calculate the next value 
assign next_acc = remainder_acc[7:0] + excess_per_bin_reminder;

wire [7:0] prev_bin;
wire [11:0] current_write_addr;
assign prev_bin = tile_bin_cnt[7:0] - 8'd1;
assign current_write_addr = {tile_cnt, prev_bin};

wire [3:0] next_tile_id;
assign next_tile_id =  tile_cnt + 4'd1;

assign rd_bram_addr = {tile_cnt, tile_bin_cnt[7:0]};






localparam  [2:0]   idle  = 3'b000,
                    read_histo_and_clip = 3'b001,  // address for read and check and compute the excess_total
                    check_excess = 3'b011, // one delay cylce just to estimate the excess at the correct timing
                    redestribute_tile = 3'b010,  // redestribute the excess_total
                    next_tile = 3'b100,  // to reinitialize the counters
                    done = 3'b101;  // clip_done = 1

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
        if(hist_ready)
         begin
          next_state = read_histo_and_clip;   
         end

      end

   read_histo_and_clip:
      begin
        if(tile_bin_cnt == 256)
          next_state = check_excess;   // always go here first
        else
          next_state = read_histo_and_clip;
      end   
       
   check_excess:
      begin
        if(excess_total > 0)
           next_state = redestribute_tile;
        else
           next_state = next_tile;
      end      

   redestribute_tile:
      begin
        if(tile_bin_cnt == 256)
         next_state = next_tile;
      end

   next_tile:
      begin
        if(tile_cnt == 15)
         next_state = done;
        else 
         next_state = read_histo_and_clip;
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
      tile_cnt <= 4'b0;
      tile_bin_cnt <= 9'b0;
      clip_ready <= 1'b0;
      //rd_bram_addr <= 12'b0;
      wr_bram_addr <= 12'b0;
      wr_bram_data <= 16'b0;
      wr_bram_en <= 1'b0;
      excess_total <= 16'b0;
      remainder_acc <= 9'd255; // to overflow in the next cycle immediately.
    end

   else
    begin
      case(current_state)
      idle:
         begin
            tile_cnt <= 4'b0;
            tile_bin_cnt <= 9'b0;
            //rd_bram_addr <= 12'b0;
            wr_bram_addr <= 12'b0;
            wr_bram_data <= 16'b0;
            wr_bram_en <= 1'b0;
            excess_total <= 16'b0;
            clip_ready <= 1'b0;
            remainder_acc <= 9'd255;
         
         end

      read_histo_and_clip:
         begin
            if(tile_bin_cnt == 9'b0)
             begin
               //rd_bram_addr <= {tile_cnt, tile_bin_cnt[7:0]};
               tile_bin_cnt <= tile_bin_cnt + 1;
             end  

            else if (tile_bin_cnt < 256)
             begin
               //rd_bram_addr <= {tile_cnt, tile_bin_cnt[7:0]};
               if(rd_bram_data > CLIP_LIMIT)
                begin
                  excess_total <= excess_total + rd_bram_data - CLIP_LIMIT;
                  wr_bram_addr <= current_write_addr;
                  wr_bram_en <= 1'b1;
                  wr_bram_data <= CLIP_LIMIT;
                end
               else
                begin
                 wr_bram_addr <= current_write_addr;
                 wr_bram_en <= 1'b1;
                 wr_bram_data <= rd_bram_data; // i think i do not have to write. could just keep the old value
                end     
               tile_bin_cnt <= tile_bin_cnt + 1; 
             end  
            else if (tile_bin_cnt == 256)
             begin
               if(rd_bram_data > CLIP_LIMIT)
                begin
                  excess_total <= excess_total + rd_bram_data - CLIP_LIMIT;
                  wr_bram_addr <= current_write_addr;
                  wr_bram_en <= 1'b1;
                  wr_bram_data <= CLIP_LIMIT;
                end
               else
                begin
                 wr_bram_addr <= current_write_addr;
                 wr_bram_en <= 1'b1;
                 wr_bram_data <= rd_bram_data; // i think i do not have to write. could just keep the old value
                end     
               tile_bin_cnt <= 0;
             end   
             

         end
      check_excess:
         begin
          // no logic, just a delay 1 cycle
          wr_bram_en <= 1'b0;
          //rd_bram_addr <= {tile_cnt, 8'b0};
         end    

      redestribute_tile:
         begin
          if(tile_bin_cnt == 9'b0)
             begin
               //rd_bram_addr <= {tile_cnt, tile_bin_cnt[7:0]};
               tile_bin_cnt <= tile_bin_cnt + 1;
               wr_bram_en <= 1'b0;
             end
           else if (tile_bin_cnt < 256)
            begin
               //rd_bram_addr <= {tile_cnt, tile_bin_cnt[7:0]};
              
                wr_bram_addr <= current_write_addr;
                wr_bram_en <= 1'b1;
                wr_bram_data <= rd_bram_data + excess_per_bin + next_acc[8];

                remainder_acc <= next_acc;   
                tile_bin_cnt <= tile_bin_cnt + 1; 
            end   
           else if (tile_bin_cnt == 256)
            begin             
              wr_bram_addr <= current_write_addr;
              wr_bram_en <= 1'b1;
              wr_bram_data <= rd_bram_data + excess_per_bin + next_acc[8];
              tile_bin_cnt <= 9'b0;
            end    
         end

      next_tile:
         begin
          if(tile_cnt < 15)
          begin
           tile_cnt <= tile_cnt + 4'd1;
          end 
          tile_bin_cnt <= 9'b0;
          //rd_bram_addr <= {next_tile_id, 8'b0};
          wr_bram_addr <= 12'b0;
          wr_bram_data <= 16'b0;
          wr_bram_en <= 1'b0;
          excess_total <= 16'b0;
          remainder_acc <= 9'd255;
          
         end

      done:
         begin
          clip_ready <= 1'b1;
         end

      default:
         begin
          tile_cnt <= 4'b0;
          tile_bin_cnt <= 9'b0;
          clip_ready <= 1'b0;
          //rd_bram_addr <= 12'b0;
          wr_bram_addr <= 12'b0;
          wr_bram_data <= 16'b0;
          wr_bram_en <= 1'b0;
          excess_total <= 16'b0;
          remainder_acc <= 9'd255;
         end

      endcase 
      end
   end   

   always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) begin
            clipping_mode <= 1'b0;
        end else if (hist_ready) begin
            clipping_mode <= 1'b1; // Turn ON clipping control
        end else if (clip_ready) begin
            clipping_mode <= 1'b0; // Turn OFF clipping control
        end
    end
endmodule