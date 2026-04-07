module TILE_GENERATION #(
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter TILE_H_NUM = 4,
    parameter TILE_V_NUM = 4
    )
(
    input   wire              clk,
    input   wire              rst_n,

    input   wire              pixel_v,      // valid signal
    input   wire  [7:0]       pixel_in,     // data_in

   // input   wire              tuser,      // start of frame
   // input   wire              tlast,      // end of line

    output  reg   [10:0]      x_count,      // pixel's horizontal coordinates (0:IMG_WIDTH - 1)
    output  reg   [9:0]       y_count,      // pixel's vertical coordinates (0:IMG_HEIGHT - 1)
    output  reg   [1:0]       tile_x,       // tile's  horizontal index (0:TILE_H_NUM - 1)
    output  reg   [1:0]       tile_y,       // tile's  vertical index (0:TILE_V_NUM - 1)
    output  reg   [3:0]       tile_idx,     // tile's  total index (0:TILE_V_NUM - 1)
    output  reg   [8:0]       tile_x_count, // pixel's horizontal coordinates in its tile (0:TILE_WIDTH - 1)
    output  reg   [7:0]       tile_y_count, // pixel's vertical coordinates in its tile (0:TILE_HEIGHT - 1)
    output  reg   [7:0]       pixel_out     // data_out
    output  reg               pixel_v_out,      // valid out
);

 localparam TILE_WIDTH = IMG_WIDTH / TILE_H_NUM;    // 320
 localparam TILE_HEIGHT = IMG_HEIGHT / TILE_V_NUM;  // 180



 always @(posedge clk or negedge rst_n)
 begin
    if (!rst_n)
    begin
        x_count <= 0;
        y_count <= 0;
        tile_x <= 0;
        tile_y <= 0;
        tile_idx <= 0;
    end 
    else 
    begin
        if (pixel_v)
        begin
            if (x_count < IMG_WIDTH - 1)
                 x_count <= x_count + 1;
            else
            begin
                x_count <= 0;
                if (y_count < IMG_HEIGHT - 1)
                    y_count <= y_count + 1;
                else
                    y_count <= 0;
            end
        end            
    end
    
 end

 always @(posedge clk or negedge rst_n) 
 begin
    if (!rst_n)
    begin
        tile_x_count <= 0;
        tile_y_count <= 0;
    end
    else
    begin
        if (pixel_v)
        begin
            if (tile_x_count < TILE_WIDTH - 1)
                 tile_x_count <= tile_x_count + 1;
            else
                tile_x_count <= 0;
                if (tile_y_count < TILE_HEIGHT - 1)
                     tile_y_count <= tile_y_count + 1;
                else
                    tile_y_count <= 0;
        end
    end
    
 end

 always@(*)
  begin
    if (x_count < 320)
        tile_x = 0;
    else if (x_count < 640)
        tile_x = 1;
    else if (x_count < 960)
        tile_x = 2;
    else
        tile_x = 3;
  end

    always@(*)
    begin
        if (y_count < 180)
            tile_y = 0;
        else if (y_count < 360)
            tile_y = 1;
        else if (y_count < 540)
            tile_y = 2;
        else
            tile_y = 3;
    end

    always@(*)    
    begin
        tile_idx = {tile_y, tile_x}; // concatenate tile_y and tile_x to get tile_idx
    end

    always@(posedge clk or negedge rst_n)
     begin
        if (!rst_n)
           pixel_out <= 8'b0;
           pixel_v_out <= 0;
        else if (pixel_v)   
           pixel_out <= pixel_in;
           pixel_v_out <= pixel_v;
     end   





endmodule

