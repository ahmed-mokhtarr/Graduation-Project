module pixel_counter #(
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720
    )
(
    input   wire              clk,
    input   wire              rst_n,

    input   wire              pixel_v,      // valid signal
    input   wire  [7:0]       pixel_in,     // data_in


    output  reg   [10:0]      x_count,      // pixel's horizontal coordinates (0:IMG_WIDTH - 1)
    output  reg   [9:0]       y_count,      // pixel's vertical coordinates (0:IMG_HEIGHT - 1)
    output  reg   [7:0]       pixel_out,     // data_out
    output  reg               pixel_v_out     // valid out
);

 reg [10:0] reg_x_count;
 reg [9:0]  reg_y_count;

 always @(posedge clk or negedge rst_n)
 begin
    if (!rst_n)
    begin
        reg_x_count <= 0;
        reg_y_count <= 0;
        x_count <= 0;
        y_count <= 0;
    end 
    else 
     begin

        x_count <= reg_x_count;
        y_count <= reg_y_count;

        if (pixel_v)
        begin
            if (reg_x_count < IMG_WIDTH - 1)
                 reg_x_count <= reg_x_count + 1;
            else
             begin
                reg_x_count <= 0;
                if (reg_y_count < IMG_HEIGHT - 1)
                    reg_y_count <= reg_y_count + 1;
                else
                    reg_y_count <= 0;
             end
        end            
     end
    
 end

 always@(posedge clk or negedge rst_n)
     begin
        if (!rst_n)
          begin
           pixel_out <= 8'b0;
           pixel_v_out <= 0;
          end 
        else    
          begin
           pixel_out <= pixel_in;
           pixel_v_out <= pixel_v;
          end 
     end 
endmodule