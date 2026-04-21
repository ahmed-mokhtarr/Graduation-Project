module bilinear_interpolation
(
    input   wire               clk,
    input   wire               rst_n,

    input   wire   [7:0]       pixel_in,       
    input   wire               pixel_v,       
    input   wire   [10:0]      x_count,      // pixel's horizontal coordinates (0:IMG_WIDTH - 1)
    input   wire   [9:0]       y_count,      // pixel's vertical coordinates (0:IMG_HEIGHT - 1)       


 
    output reg     [7:0]      rd_bram_addr,
    
    output reg     [3:0]      tl_idx,      // top_left
    output reg     [3:0]      tr_idx,      // top_right
    output reg     [3:0]      bl_idx,      // bottom_left
    output reg     [3:0]      br_idx,      // bottom_right

    input  wire    [7:0]      tl_data,
    input  wire    [7:0]      tr_data,
    input  wire    [7:0]      bl_data,
    input  wire    [7:0]      br_data,

    output reg     [7:0]      pixel_out,
    output reg                pixel_v_out
);


// First Stage - Clamp coordinates & broadcast BRAM read address
reg [10:0]  calc_x;  // The taken x_count to work on
reg [9:0]   calc_y;   // The taken y_count to work on
reg         v_s1;     // valid_delayed

always @(posedge clk or negedge rst_n)
 begin
    if(!rst_n)
     begin
        calc_x <= 0;
        calc_y <= 0;
        v_s1 <= 0;
        rd_bram_addr <= 0;
     end   
    else
     begin
        calc_x <= (x_count < 11'd160 ) ? 11'd160 : 
                  (x_count > 11'd1120) ? 11'd1120 : x_count;

        calc_y <= (y_count < 10'd90 ) ? 10'd90 : 
                  (y_count > 10'd630) ? 10'd630 : y_count;

        v_s1 <= pixel_v;
        rd_bram_addr <= pixel_in;
     end
 end   

 // Second Stage - Detecting in which zone and then computing the IDs for the 4 surrounding tiles
reg [1:0] left_col, right_col;
reg [1:0] top_row,  bot_row;
reg [8:0] dx;   // x-distance from left tile center 
reg [7:0] dy;   // y-distance from top tile center 

always @(*)
 begin
    // X Zone
    if(calc_x < 480)
     begin
       left_col = 2'd0;
       right_col = 2'd1;

       dx = calc_x - 11'd160; 
     end
    else if(calc_x < 800)
     begin
       left_col = 2'd1;
       right_col = 2'd2;

       dx = calc_x - 11'd480; 
     end
    else   
     begin
       left_col = 2'd2;
       right_col = 2'd3;

       dx = calc_x - 11'd800; 
     end

    // Y Zone
     if(calc_y < 270)
     begin
       top_row = 2'd0;
       bot_row = 2'd1;

       dy = calc_y - 10'd90; 
     end
    else if(calc_y < 450)
     begin
       top_row = 2'd1;
       bot_row = 2'd2;

       dy = calc_y - 10'd270; 
     end
    else   
     begin
       top_row = 2'd2;
       bot_row = 2'd3;

       dy = calc_y - 10'd450; 
     end   
 end


reg [8:0] x_weight;   // x_weight = (dx * (256/320) * 1024 + (1024/2)) / 1024 -> (0:256)
reg [8:0] y_weight;   // y_weight = (dy * (256/180) * 1024 + (1024/2)) / 1024 -> (0:256)
reg       v_s2;

always @(posedge clk or negedge rst_n)
 begin
    if(!rst_n)
     begin
      tl_idx <= 4'd0;
      tr_idx <= 4'd0;
      bl_idx <= 4'd0;
      br_idx <= 4'd0;
      x_weight <= 9'd0;
      y_weight <= 9'd0;
      v_s2 <= 1'd0;
     end   
    else
     begin
      tl_idx <= {top_row, left_col};
      tr_idx <= {top_row, right_col};
      bl_idx <= {bot_row, left_col};
      br_idx <= {bot_row, right_col};
      x_weight <= ({11'b0, dx} * 20'd819  + 20'd512) >> 10; // 819 = (256/320) * 1024, and 512 is for rounding
      y_weight <= ({12'b0, dy} * 20'd1456 + 20'd512) >> 10; // 1456 = (256/180) * 1024, and 512 is for rounding
      v_s2 <= v_s1;  
     end    
 end   

// Third Stage - Register the MUXed BRAM outputs from top module
reg [7:0] TL_reg, TR_reg, BL_reg, BR_reg;
reg [8:0] x_w_s3, y_w_s3;
reg       v_s3;
 
always @(posedge clk or negedge rst_n) 
 begin
    if(!rst_n) 
     begin
        TL_reg <= 8'd0; 
        TR_reg <= 8'd0;
        BL_reg <= 8'd0; 
        BR_reg <= 8'd0;
        x_w_s3 <= 9'd0; 
        y_w_s3 <= 9'd0;
        v_s3   <= 1'b0;
     end else 
      begin
        TL_reg <= tl_data;
        TR_reg <= tr_data;
        BL_reg <= bl_data;
        BR_reg <= br_data;
        x_w_s3 <= x_weight;
        y_w_s3 <= y_weight;
        v_s3 <= v_s2;
     end
 end


// Fourth Stage - Horizontal interpolation
reg [15:0] interp_x_top, interp_x_bot;
reg [8:0]  y_w_s4;
reg        v_s4;
 
always @(posedge clk or negedge rst_n) 
 begin
    if (!rst_n) begin
        interp_x_top <= 16'd0; 
        interp_x_bot <= 16'd0;
        y_w_s4  <=  9'd0; 
        v_s4   <=  1'b0;
    end else 
     begin
        interp_x_top <= (TL_reg * (9'd256 - x_w_s3)) + (TR_reg * x_w_s3);
        interp_x_bot <= (BL_reg * (9'd256 - x_w_s3)) + (BR_reg * x_w_s3);
        y_w_s4 <= y_w_s3;
        v_s4 <= v_s3;
     end
 end

// Fifth Stage - Vertical interpolation
reg [23:0] interp_y_final;
reg        v_s5;
 
always @(posedge clk or negedge rst_n) 
 begin
    if (!rst_n) 
     begin
        interp_y_final <= 24'd0;
        v_s5 <=  1'b0;
     end 
    else 
     begin
        interp_y_final <= (interp_x_top * (9'd256 - y_w_s4)) + (interp_x_bot * y_w_s4);
        v_s5 <= v_s4;
     end
 end


// Fifth Stage - Output pixel
always @(posedge clk or negedge rst_n) 
 begin
    if (!rst_n) 
     begin
        pixel_out   <= 8'd0;
        pixel_v_out <= 1'b0;
     end 
    else 
     begin
        pixel_out <= interp_y_final[23:16];
        pixel_v_out <= v_s5;
     end
 end




endmodule