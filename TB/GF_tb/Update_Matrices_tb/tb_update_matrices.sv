`timescale 1ns / 1ps

module tb_update_matrices();

    // Parameters matching the design
    parameter W_R2 = 47;
    parameter W_R3 = 49;
    parameter W_R4 = 46;
    parameter W_R5 = 49;
    parameter W_R6 = 47;

    // Calculated parameters
    parameter W_DB_X = W_R2 + 1;
    parameter W_DB_Y = W_R3 + 1;
    parameter W_A11  = W_R4 + 1;
    parameter W_A22  = W_R5 + 1;
    parameter W_A12  = W_R6 + 1;

    parameter W_A11_SQ = 2 * W_A11;
    parameter W_A22_SQ = 2 * W_A22;
    parameter W_A12_SQ = 2 * W_A12;

    parameter W_H1_T1 = W_A11 + W_DB_X;
    parameter W_H1_T2 = W_A12 + W_DB_Y;
    parameter W_H2_T1 = W_A12 + W_DB_X;
    parameter W_H2_T2 = W_A22 + W_DB_Y;

    parameter W_A_TRACE = (W_A11 > W_A22 ? W_A11 : W_A22) + 1;

    parameter W_G11 = (W_A11_SQ > W_A12_SQ ? W_A11_SQ : W_A12_SQ) + 1;
    parameter W_G22 = (W_A12_SQ > W_A22_SQ ? W_A12_SQ : W_A22_SQ) + 1;
    parameter W_G12 = W_A12 + W_A_TRACE;

    parameter W_H1 = (W_H1_T1 > W_H1_T2 ? W_H1_T1 : W_H1_T2) + 1;
    parameter W_H2 = (W_H2_T1 > W_H2_T2 ? W_H2_T1 : W_H2_T2) + 1;

    // Clock and Reset
    reg clk;
    reg rst_n;

    // Inputs
    reg valid_in;
    reg signed [W_R2-1:0] prev_frame_r2, curr_frame_r2;
    reg signed [W_R3-1:0] prev_frame_r3, curr_frame_r3;
    reg signed [W_R4-1:0] prev_frame_r4, curr_frame_r4;
    reg signed [W_R5-1:0] prev_frame_r5, curr_frame_r5;
    reg signed [W_R6-1:0] prev_frame_r6, curr_frame_r6;

    // Outputs
    wire valid_out;
    wire signed [W_G11-1:0] matrix_G11_out;
    wire signed [W_G12-1:0] matrix_G12_out;
    wire signed [W_G22-1:0] matrix_G22_out;
    wire signed [W_H1-1:0] vector_h1_out;
    wire signed [W_H2-1:0] vector_h2_out;

    // File Pointers & Scan Status
    integer fd_in1, fd_in2, fd_out;
    integer scan_f1, scan_f2;

    // Instantiate DUT
    update_matrices uut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .prev_frame_r2(prev_frame_r2), .prev_frame_r3(prev_frame_r3),
        .prev_frame_r4(prev_frame_r4), .prev_frame_r5(prev_frame_r5),
        .prev_frame_r6(prev_frame_r6),
        .curr_frame_r2(curr_frame_r2), .curr_frame_r3(curr_frame_r3),
        .curr_frame_r4(curr_frame_r4), .curr_frame_r5(curr_frame_r5),
        .curr_frame_r6(curr_frame_r6),
        .valid_out(valid_out),
        .matrix_G11_out(matrix_G11_out),
        .matrix_G12_out(matrix_G12_out),
        .matrix_G22_out(matrix_G22_out),
        .vector_h1_out(vector_h1_out),
        .vector_h2_out(vector_h2_out)
    );

    // Clock Generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Stimulus process
    initial begin
        // Initialize
        rst_n = 0;
        valid_in = 0;
        prev_frame_r2 = 0; prev_frame_r3 = 0; prev_frame_r4 = 0; prev_frame_r5 = 0; prev_frame_r6 = 0;
        curr_frame_r2 = 0; curr_frame_r3 = 0; curr_frame_r4 = 0; curr_frame_r5 = 0; curr_frame_r6 = 0;

        // Open Files
        fd_in1 = $fopen("input_frame1.txt", "r");
        fd_in2 = $fopen("input_frame2.txt", "r");
        
        if (fd_in1 == 0 || fd_in2 == 0) begin
            $display("ERROR: Could not open input stimulus files.");
            $finish;
        end
        
        fd_out = $fopen("tb_outputs.txt", "w");

        // Apply Reset
        #20 rst_n = 1;
        #10;

        // Read stimulus and drive
        while (!$feof(fd_in1) && !$feof(fd_in2)) begin
            @(posedge clk);
            
            // Read from Frame 1 file
            scan_f1 = $fscanf(fd_in1, "%x %x %x %x %x\n", 
                              prev_frame_r2, prev_frame_r3, prev_frame_r4, prev_frame_r5, prev_frame_r6);
                              
            // Read from Frame 2 file
            scan_f2 = $fscanf(fd_in2, "%x %x %x %x %x\n", 
                              
                              curr_frame_r2, curr_frame_r3, curr_frame_r4, curr_frame_r5, curr_frame_r6);

            // Assert valid_in if both files successfully yielded a line
            if (scan_f1 == 5 && scan_f2 == 5) begin
                valid_in    <= 1'b1;
            end else begin
                valid_in    <= 1'b0;
            end
        end

        // De-assert valid and wait for pipeline to flush (3 cycles)
        @(posedge clk);
        valid_in <= 1'b0;
        #50;
        
        $fclose(fd_in1);
        $fclose(fd_in2);
        $fclose(fd_out);
        $display("Simulation Complete.");
        $stop;
    end

    // Output capture process
    always @(posedge clk) begin
        if (valid_out) begin
            $fwrite(fd_out, "%0x %0x %0x %0x %0x\n", 
                     matrix_G11_out, matrix_G12_out, matrix_G22_out, vector_h1_out, vector_h2_out);
        end
    end

endmodule