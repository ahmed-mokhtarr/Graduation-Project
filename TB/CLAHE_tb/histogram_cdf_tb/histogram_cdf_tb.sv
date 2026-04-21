`timescale 1ns / 1ps

module histogram_cdf_tb();

    reg          clk;
    reg          rst_n;

    reg          pixel_v;
    reg [7:0]    pixel_in;

    wire [11:0]  wr_bram_addr;
    wire [15:0]  wr_bram_data;
    wire         wr_bram_en;
    wire [11:0]  rd_bram_addr;
    wire         cdf_ready;

    // 2d array to hold the image
    reg [7:0] image_mem [0:921599]; 

    // Loop and File I/O variables
    integer i;
    integer t;
    integer b;
    integer file_id;

   
    clahe_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_v(pixel_v),
        .pixel_in(pixel_in),
        .wr_bram_addr(wr_bram_addr),
        .wr_bram_data(wr_bram_data),
        .wr_bram_en(wr_bram_en),
        .rd_bram_addr(rd_bram_addr),
        .cdf_ready(cdf_ready)
    );

    initial begin
        $readmemh("image_hex.txt", image_mem);
        $display("Image loaded into testbench memory.");   

        clk = 0;
        rst_n = 0;
        #15 // Hold reset for a moment, not just on the edge
        rst_n = 1;
        #10;

        // 1. Send the image to the hardware
        drive_stimulus();

        // 2. Wait for the calculation to finish
        wait(cdf_ready == 1'b1);
        $display("Histogram calculation complete!");

        // 3. Dump the results to a file
        collect_output();

        #10000;
        $stop;
    end

    // Clock generator (100 MHz)
    always #5 clk = ~clk;

    // ==========================================
    // Tasks
    // ==========================================

    task drive_stimulus;
        begin
            $display("Starting pixel stream...");
            for(i = 0; i < 921600; i = i + 1) begin
                @(negedge clk); // Sync to the falling edge for safe data driving
                pixel_v = 1'b1;
                pixel_in = image_mem[i];
            end  
            
            @(negedge clk);
            pixel_v = 1'b0; // Turn off valid after the last pixel
            $display("Frame completely sent.");
        end
    endtask

    task collect_output;
        begin
            $display("Opening hardware_cdf.txt for writing...");
            file_id = $fopen("hardware_cdf.txt", "w"); 
            
            if (file_id == 0) begin
                $display("ERROR: Could not open file.");
            end else begin
                // We loop through the tile index 't'
                for (t = 0; t < 16; t = t + 1) begin
                    // We use a CASE statement to "hardcode" the paths
                    case(t)
                        0:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[0].cdf_bram_dut.ram[b]);
                        1:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[1].cdf_bram_dut.ram[b]);
                        2:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[2].cdf_bram_dut.ram[b]);
                        3:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[3].cdf_bram_dut.ram[b]);
                        4:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[4].cdf_bram_dut.ram[b]);
                        5:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[5].cdf_bram_dut.ram[b]);
                        6:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[6].cdf_bram_dut.ram[b]);
                        7:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[7].cdf_bram_dut.ram[b]);
                        8:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[8].cdf_bram_dut.ram[b]);
                        9:  for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[9].cdf_bram_dut.ram[b]);
                        10: for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[10].cdf_bram_dut.ram[b]);
                        11: for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[11].cdf_bram_dut.ram[b]);
                        12: for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[12].cdf_bram_dut.ram[b]);
                        13: for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[13].cdf_bram_dut.ram[b]);
                        14: for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[14].cdf_bram_dut.ram[b]);
                        15: for(b=0; b<256; b++) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[15].cdf_bram_dut.ram[b]);
                    endcase
                end
                
                $fclose(file_id); 
                $display("CDF Write complete!");
            end
        end
    endtask

endmodule