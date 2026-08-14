`timescale 1ns / 1ps

module bilinear_interpolation_tb();

    reg          clk;
    reg          rst_n;

    // Pass 1 Signals
    reg          pixel_v;
    reg  [7:0]   pixel_in;

    // Pass 2 Signals (NEW)
    reg          interp_pixel_v;
    reg  [7:0]   interp_pixel_in;
    wire [7:0]   final_pixel_out;
    wire         final_pixel_v_out;

    // Top Level External BRAM/Status signals
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
    integer out_file_id; // NEW: For the final image output

    clahe_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        // Pass 1
        .pixel_v(pixel_v),
        .pixel_in(pixel_in),
        // Pass 2
        .interp_pixel_v_in(interp_pixel_v),
        .interp_pixel_in(interp_pixel_in),
        .final_pixel_out(final_pixel_out),
        .final_pixel_v_out(final_pixel_v_out),
        // BRAM / Status
        .wr_bram_addr(wr_bram_addr),
        .wr_bram_data(wr_bram_data),
        .wr_bram_en(wr_bram_en),
        .rd_bram_addr(rd_bram_addr),
        .cdf_ready(cdf_ready)
    );

    initial begin
        // Open the output file for Pass 2 early
        out_file_id = $fopen("hardware_interp_output.txt", "w");
        if (out_file_id == 0) $display("ERROR: Could not open output file.");

        $readmemh("image_hex.txt", image_mem);
        $display("Image loaded into testbench memory.");   

        clk = 0;
        rst_n = 0;
        pixel_v = 0;
        pixel_in = 0;
        interp_pixel_v = 0;
        interp_pixel_in = 0;

        #15 // Hold reset for a moment, not just on the edge
        rst_n = 1;
        #10;

        // 1. PASS 1: Send the image to build Histograms/CDFs
        drive_stimulus();

        // 2. Wait for the CDF calculation to finish
        wait(cdf_ready == 1'b1);
        $display("Histogram & CDF calculation complete!");

        // 3. Dump the CDF results to a file
        collect_output();

        // Small delay to simulate processor turnaround between frames
        #200;

        // 4. PASS 2: Send the image again to push it through the Interpolator
        drive_interp_stimulus();

        // 5. Wait for the pipeline to flush (Interpolator takes 6 clock cycles)
        #1000000
        
        $fclose(out_file_id);
        $display("Simulation complete! Output saved to hardware_interp_output.txt.");
        $stop;
    end

    // Clock generator (100 MHz)
    always #5 clk = ~clk;

    // ==========================================
    // Real-Time Output Capture (NEW)
    // ==========================================
    always @(negedge clk) begin
        // Whenever the interpolator spits out a valid pixel, write it to the file
        if (final_pixel_v_out) begin
            $fdisplay(out_file_id, "%d", final_pixel_out);
        end
    end

    // ==========================================
    // Tasks
    // ==========================================

    task drive_stimulus;
        begin
            $display("Starting Pass 1 (CDF Build) pixel stream...");
            for(i = 0; i < 921600; i = i + 1) begin
                @(negedge clk); // Sync to the falling edge for safe data driving
                pixel_v = 1'b1;
                pixel_in = image_mem[i];
            end  
            
            @(negedge clk);
            pixel_v = 1'b0; // Turn off valid after the last pixel
            $display("Pass 1 Frame completely sent.");
        end
    endtask

    task drive_interp_stimulus;
        begin
            $display("Starting Pass 2 (Interpolation) pixel stream...");
            for(i = 0; i < 921600; i = i + 1) begin
                @(negedge clk); 
                interp_pixel_v = 1'b1;
                interp_pixel_in = image_mem[i];
            end  
            
            @(negedge clk);
            interp_pixel_v = 1'b0; 
            $display("Pass 2 Frame completely sent.");
        end
    endtask

    task collect_output;
        begin
            $display("Opening hardware_cdf.txt for writing...");
            file_id = $fopen("hardware_cdf.txt", "w"); 
            
            if (file_id == 0) begin
                $display("ERROR: Could not open file.");
            end else begin
                // Loop through the tile index 't'
                for (t = 0; t < 16; t = t + 1) begin
                    case(t)
                        0:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[0].cdf_bram_dut.ram[b]);
                        1:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[1].cdf_bram_dut.ram[b]);
                        2:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[2].cdf_bram_dut.ram[b]);
                        3:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[3].cdf_bram_dut.ram[b]);
                        4:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[4].cdf_bram_dut.ram[b]);
                        5:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[5].cdf_bram_dut.ram[b]);
                        6:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[6].cdf_bram_dut.ram[b]);
                        7:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[7].cdf_bram_dut.ram[b]);
                        8:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[8].cdf_bram_dut.ram[b]);
                        9:  for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[9].cdf_bram_dut.ram[b]);
                        10: for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[10].cdf_bram_dut.ram[b]);
                        11: for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[11].cdf_bram_dut.ram[b]);
                        12: for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[12].cdf_bram_dut.ram[b]);
                        13: for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[13].cdf_bram_dut.ram[b]);
                        14: for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[14].cdf_bram_dut.ram[b]);
                        15: for(b=0; b<256; b=b+1) $fdisplay(file_id, "%d", u_dut.CDF_BRAM_ARRAY[15].cdf_bram_dut.ram[b]);
                    endcase
                end
                
                $fclose(file_id); 
                $display("CDF Write complete!");
            end
        end
    endtask

endmodule