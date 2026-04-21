`timescale 1ns / 1ps

module histogram_generation_tb();

    reg          clk;
    reg          rst_n;

    reg          pixel_v;
    reg [7:0]    pixel_in;

    wire [11:0]  wr_bram_addr;
    wire [15:0]  wr_bram_data;
    wire         wr_bram_en;
    wire [11:0]  rd_bram_addr;
    wire         hist_ready;

    // 2d array to hold the image
    reg [7:0] image_mem [0:921599]; 

    // Loop and File I/O variables
    integer i;
    integer j;
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
        .hist_ready(hist_ready)
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
        wait(hist_ready == 1'b1);
        $display("Histogram calculation complete!");

        // 3. Dump the results to a file
        collect_output();

        #100;
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
            $display("Opening hardware_histogram.txt for writing...");
            file_id = $fopen("hardware_histogram.txt", "w"); 
            
            if (file_id == 0) begin
                $display("ERROR: Could not open file.");
            end else begin
                // Loop through the 4096 addresses of your BRAM
                for (j = 0; j < 4096; j = j + 1) begin
                    // Assuming your internal instance is named 'bram_dut' and its memory array is 'ram'
                    $fdisplay(file_id, "%d", u_dut.bram_dut.ram[j]);
                end
                
                $fclose(file_id); 
                $display("Write complete! Hardware results saved successfully.");
            end
        end
    endtask

endmodule