module CLIPPING_REDISTRIBUTION 
(
    input   wire              clk,
    input   wire              rst_n,

    input   wire              hist_ready,         // valid signal
    input   wire   [7:0]      pixel_in,           // data_in
    input   wire   [3:0]      tile_idx,

    output reg                hist_ready,
    output reg     [3:0]      ready_tile_idx

    
);



localparam  [1:0]   idle  = 3'b000,
                    issue_read = 3'b001,  // address for read
                    check_limit = 3'b011,  // check and compute the excess
                    redestribute_tile = 3'b010,  // redestribute the excess
                    done = 3'b100;  // clip_done = 1

reg  [2:0]  current_state , next_state;

always @(posedge clk or negedge rst_n)
  begin
    if(!RST)
      current_state <= idle;
    else 
      current_state <= next_state;
  end


always @(*)
 begin
   case(current_state)
   idle:
   issue_read:
   check_limit:
   redestribute_tile:
   done:
   endcase 
 end   
endmodule