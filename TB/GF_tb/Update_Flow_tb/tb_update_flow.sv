`timescale 1ns / 1ps

module tb_update_flow();

    // --------------------------------------------------------
    // Image Parameters (Layer 4)
    // --------------------------------------------------------
    parameter IMG_WIDTH  = 80;
    parameter IMG_HEIGHT = 45;
    parameter NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    
    // Boundary padding needed for 15-tap filter (radius 7)
    parameter PAD = 7; 

    // --------------------------------------------------------
    // Testbench Signals
    // --------------------------------------------------------
    logic        clk;
    logic        rst_n;
    logic        valid_in;
    logic [2:0]  layer_config;

    logic signed [96:0]  G11_in;
    logic signed [100:0] G22_in;
    logic signed [98:0]  G12_in;
    logic signed [98:0]  h1_in;
    logic signed [100:0] h2_in;

    logic                valid_out;
    logic signed [216:0] delta_x_out;
    logic signed [214:0] delta_y_out;

    // File I/O
    integer fd_in, fd_out, scan_status;
    integer output_count;

    // --------------------------------------------------------
    // Device Under Test (DUT)
    // --------------------------------------------------------
    update_flow uut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .layer_config(layer_config),
        .G11_in(G11_in),
        .G22_in(G22_in),
        .G12_in(G12_in),
        .h1_in(h1_in),
        .h2_in(h2_in),
        .valid_out(valid_out),
        .delta_x_out(delta_x_out),
        .delta_y_out(delta_y_out)
    );

    // --------------------------------------------------------
    // Clock Generation
    // --------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --------------------------------------------------------
    // Output Capture
    // --------------------------------------------------------
    initial begin
        fd_out = $fopen("tb_deltas.txt", "w");
        output_count = 0;
    end

    always @(posedge clk) begin
        if (valid_out && output_count < NUM_PIXELS) begin
            $fwrite(fd_out, "%0x %0x\n", delta_x_out, delta_y_out);
            output_count = output_count + 1;
        end
    end

    // --------------------------------------------------------
    // Stimulus Generation
    // --------------------------------------------------------
    initial begin
        rst_n        = 0;
        valid_in     = 0;
        layer_config = 3'd4; // Layer 4
        G11_in = 0; G22_in = 0; G12_in = 0; h1_in = 0; h2_in = 0;

        fd_in = $fopen("input_matrices.txt", "r");
        if (fd_in == 0) begin
            $display("ERROR: Could not open input_matrices.txt");
            $finish;
        end

        #20 rst_n = 1;
        #10;

        $display("Streaming video data through pipeline...");

        // Loop through Active Rows ONLY
        for (int y = 0; y < IMG_HEIGHT; y++) begin
            
            @(posedge clk);

            // Loop through Active Cols + 7 Pad Cols
            for (int x = 0; x < IMG_WIDTH + PAD; x++) begin
                @(posedge clk);

                if (x < IMG_WIDTH) begin
                    // Read actual image data
                    scan_status = $fscanf(fd_in, "%x %x %x %x %x\n", G11_in, G22_in, G12_in, h1_in, h2_in);
                    valid_in <= 1;
                end else begin
                    // Horizontal pad: turn off valid_in
                    valid_in <= 0;
                    G11_in <= 0; G22_in <= 0; G12_in <= 0; h1_in <= 0; h2_in <= 0;
                end
            end
            
            // End of row reset
            @(posedge clk);
            valid_in  <= 0;
        end

        #15000; // Let final stages drain (including auto vertical padding)
        $display("Simulation complete. Captured %0d valid outputs.", output_count);
        $fclose(fd_in);
        $fclose(fd_out);
        $stop;
    end

endmodule