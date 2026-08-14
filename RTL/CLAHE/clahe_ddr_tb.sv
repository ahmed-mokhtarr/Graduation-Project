`timescale 1ns / 1ps
// ============================================================================
//  CLAHE DDR Testbench
//  - Sends 2 frames through the DDR-based CLAHE pipeline
//  - Frame 0's enhanced output appears during Frame 1's input
//  - Uses axi_slave_mem_model as a behavioral DDR substitute
// ============================================================================
module clahe_ddr_tb();

    // -----------------------------------------------------------------
    //  Clock & Reset
    // -----------------------------------------------------------------
    reg          clk;
    reg          rst_n;

    // -----------------------------------------------------------------
    //  DUT  I/O
    // -----------------------------------------------------------------
    reg          frame_start;
    reg          pixel_v;
    reg  [7:0]   pixel_in;

    wire [7:0]   final_pixel_out;
    wire         final_pixel_v_out;
    wire         cdf_ready;

    // AXI wires between DUT and memory model
    wire [31:0]  axi_awaddr,  axi_araddr;
    wire [7:0]   axi_awlen,   axi_arlen;
    wire [2:0]   axi_awsize,  axi_arsize;
    wire [1:0]   axi_awburst, axi_arburst;
    wire         axi_awvalid, axi_arvalid;
    wire         axi_awready, axi_arready;
    wire [31:0]  axi_wdata,   axi_rdata;
    wire [3:0]   axi_wstrb;
    wire         axi_wlast,   axi_rlast;
    wire         axi_wvalid,  axi_rvalid;
    wire         axi_wready,  axi_rready;
    wire [1:0]   axi_bresp,   axi_rresp;
    wire         axi_bvalid;
    wire         axi_bready;

    // -----------------------------------------------------------------
    //  Image memory (in testbench)
    // -----------------------------------------------------------------
    reg [7:0] image_mem_0 [0:921599];   // Frame 0
    reg [7:0] image_mem_1 [0:921599];   // Frame 1
    reg [7:0] image_mem_2 [0:921599];   // Frame 2

    // -----------------------------------------------------------------
    //  Loop / File I/O variables
    // -----------------------------------------------------------------
    integer i, t, b;
    integer cdf_file_id;
    integer out_file_id;
    integer pixel_out_count;

    // =================================================================
    //  DUT Instantiation
    // =================================================================
    clahe_top #(
        .DDR_BASE_A(32'h1000_0000),
        .DDR_BASE_B(32'h1010_0000)
    ) u_dut (
        .clk               (clk),
        .rst_n              (rst_n),
        .frame_start        (frame_start),
        .pixel_v            (pixel_v),
        .pixel_in           (pixel_in),

        .final_pixel_out    (final_pixel_out),
        .final_pixel_v_out  (final_pixel_v_out),
        .cdf_ready          (cdf_ready),

        // AXI Write
        .m_axi_awaddr       (axi_awaddr),
        .m_axi_awlen        (axi_awlen),
        .m_axi_awsize       (axi_awsize),
        .m_axi_awburst      (axi_awburst),
        .m_axi_awvalid      (axi_awvalid),
        .m_axi_awready      (axi_awready),
        .m_axi_wdata        (axi_wdata),
        .m_axi_wstrb        (axi_wstrb),
        .m_axi_wlast        (axi_wlast),
        .m_axi_wvalid       (axi_wvalid),
        .m_axi_wready       (axi_wready),
        .m_axi_bresp        (axi_bresp),
        .m_axi_bvalid       (axi_bvalid),
        .m_axi_bready       (axi_bready),

        // AXI Read
        .m_axi_araddr       (axi_araddr),
        .m_axi_arlen        (axi_arlen),
        .m_axi_arsize       (axi_arsize),
        .m_axi_arburst      (axi_arburst),
        .m_axi_arvalid      (axi_arvalid),
        .m_axi_arready      (axi_arready),
        .m_axi_rdata        (axi_rdata),
        .m_axi_rresp        (axi_rresp),
        .m_axi_rlast        (axi_rlast),
        .m_axi_rvalid       (axi_rvalid),
        .m_axi_rready       (axi_rready)
    );

    // =================================================================
    //  AXI Slave Memory Model  (simulates DDR)
    // =================================================================
    axi_slave_mem_model #(
        .MEM_BASE  (32'h1000_0000),
        .MEM_BYTES (2 * 1024 * 1024)        // 2 MB  (covers both frame locations)
    ) u_ddr (
        .clk            (clk),
        .rst_n          (rst_n),
        // Write
        .s_axi_awaddr   (axi_awaddr),
        .s_axi_awlen    (axi_awlen),
        .s_axi_awsize   (axi_awsize),
        .s_axi_awburst  (axi_awburst),
        .s_axi_awvalid  (axi_awvalid),
        .s_axi_awready  (axi_awready),
        .s_axi_wdata    (axi_wdata),
        .s_axi_wstrb    (axi_wstrb),
        .s_axi_wlast    (axi_wlast),
        .s_axi_wvalid   (axi_wvalid),
        .s_axi_wready   (axi_wready),
        .s_axi_bresp    (axi_bresp),
        .s_axi_bvalid   (axi_bvalid),
        .s_axi_bready   (axi_bready),
        // Read
        .s_axi_araddr   (axi_araddr),
        .s_axi_arlen    (axi_arlen),
        .s_axi_arsize   (axi_arsize),
        .s_axi_arburst  (axi_arburst),
        .s_axi_arvalid  (axi_arvalid),
        .s_axi_arready  (axi_arready),
        .s_axi_rdata    (axi_rdata),
        .s_axi_rresp    (axi_rresp),
        .s_axi_rlast    (axi_rlast),
        .s_axi_rvalid   (axi_rvalid),
        .s_axi_rready   (axi_rready)
    );

    // =================================================================
    //  Clock: 100 MHz  (10 ns period)
    // =================================================================
    always #5 clk = ~clk;

    // =================================================================
    //  Output Pixel Capture
    // =================================================================
    always @(negedge clk) begin
        if (final_pixel_v_out) begin
            $fdisplay(out_file_id, "%d", final_pixel_out);
            pixel_out_count = pixel_out_count + 1;
        end
    end

    // =================================================================
    //  Main Stimulus
    // =================================================================
    initial begin
        // Open output files
        out_file_id = $fopen("hardware_interp_output.txt", "w");
        if (out_file_id == 0) begin
            $display("ERROR: Could not open output file.");
            $finish;
        end

        // Load test images
        $readmemh("sim_data/frame0_hex.txt", image_mem_0);
        $readmemh("sim_data/frame1_hex.txt", image_mem_1);
        $readmemh("sim_data/frame2_hex.txt", image_mem_2);
        $display("[TB] Images loaded.");

        // Init
        clk         = 0;
        rst_n       = 0;
        frame_start = 0;
        pixel_v     = 0;
        pixel_in    = 0;
        pixel_out_count = 0;

        // Reset
        #20;
        rst_n = 1;
        #20;

        // ==============================================================
        //  FRAME 0  (histogram/CDF build + DDR write, NO output yet)
        // ==============================================================
        $display("[TB] ===== FRAME 0 START =====  time=%0t", $time);
        send_frame_start();
        drive_frame(0);

        // Wait for CDF pipeline to finish
        wait (cdf_ready == 1'b1);
        $display("[TB] Frame 0 CDF ready.  time=%0t", $time);

        // Dump CDF tables for verification
        collect_cdf("hardware_cdf_frame0.txt");

        // Simulate VBLANK  (processing + BRAM clear happen here automatically)
        $display("[TB] Waiting for BRAM clear (VBLANK)...");
        wait (u_dut.clear_dut.clear_done == 1'b1);
        $display("[TB] BRAM clear done.  time=%0t", $time);
        #200;  // remaining blanking

        // ==============================================================
        //  FRAME 1  (histo build + DDR write  |  DDR read Frame 0 + bilinear)
        // ==============================================================
        $display("[TB] ===== FRAME 1 START =====  time=%0t", $time);
        send_frame_start();
        fork
            drive_frame(1);
            begin
                wait (u_dut.read_frame_done == 1'b1);
                $display("[TB] Frame 0 read-back done.  Captured %0d output pixels.  time=%0t",
                         pixel_out_count, $time);
            end
        join

        // Wait for Frame 1 CDF
        wait (cdf_ready == 1'b1);
        $display("[TB] Frame 1 CDF ready.  time=%0t", $time);
        collect_cdf("hardware_cdf_frame1.txt");

        // Wait for BRAM clear
        wait (u_dut.clear_dut.clear_done == 1'b1);
        #200;

        // ==============================================================
        //  FRAME 2
        // ==============================================================
        $display("[TB] ===== FRAME 2 START =====  time=%0t", $time);
        pixel_out_count = 0;
        send_frame_start();
        fork
            drive_frame(2);
            begin
                wait (u_dut.read_frame_done == 1'b1);
                $display("[TB] Frame 1 read-back done.  Captured %0d output pixels.  time=%0t",
                         pixel_out_count, $time);
            end
        join

        // Wait for Frame 2 CDF
        wait (cdf_ready == 1'b1);
        $display("[TB] Frame 2 CDF ready.  time=%0t", $time);
        collect_cdf("hardware_cdf_frame2.txt");

        // Wait for BRAM clear
        wait (u_dut.clear_dut.clear_done == 1'b1);
        #200;
        
        // ==============================================================
        //  DUMMY FRAME TO GET FRAME 2 OUTPUT
        // ==============================================================
        $display("[TB] ===== FLUSH FRAME START =====  time=%0t", $time);
        pixel_out_count = 0;
        send_frame_start();
        // Just send zeros or anything so frame 2 gets interpolated
        fork
            drive_frame(0);
            begin
                wait (u_dut.read_frame_done == 1'b1);
                $display("[TB] Frame 2 read-back done.  Captured %0d output pixels.  time=%0t",
                         pixel_out_count, $time);
            end
        join

        // Flush pipeline
        #10000;

        $fclose(out_file_id);
        $display("[TB] ===== SIMULATION COMPLETE =====");
        $display("[TB] Output saved to hardware_interp_output.txt");
        $stop;
    end

    // =================================================================
    //  Tasks
    // =================================================================

    // Send a 1-clock frame_start pulse
    task send_frame_start;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(negedge clk);
            frame_start = 1'b0;
        end
    endtask

    // Drive a full frame of pixels (921600 pixels, 1 per clock)
    task drive_frame;
        input integer frame_id;
        begin
            $display("[TB]   Driving %0d pixels for frame %0d ...", 921600, frame_id);
            for (i = 0; i < 921600; i = i + 1) begin
                @(negedge clk);
                pixel_v  = 1'b1;
                if (frame_id == 0) pixel_in = image_mem_0[i];
                else if (frame_id == 1) pixel_in = image_mem_1[i];
                else pixel_in = image_mem_2[i];
            end
            @(negedge clk);
            pixel_v  = 1'b0;
            pixel_in = 8'd0;
            $display("[TB]   Frame %0d pixels sent.  time=%0t", frame_id, $time);
        end
    endtask

    // Dump all 16 CDF BRAM contents to a file
    task collect_cdf;
        input [256*8-1:0] filename;   // string
        begin
            cdf_file_id = $fopen(filename, "w");
            if (cdf_file_id == 0) begin
                $display("ERROR: Could not open %0s", filename);
            end else begin
                for (t = 0; t < 16; t = t + 1) begin
                    case(t)
                        0:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[0].cdf_bram_dut.ram[b]);
                        1:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[1].cdf_bram_dut.ram[b]);
                        2:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[2].cdf_bram_dut.ram[b]);
                        3:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[3].cdf_bram_dut.ram[b]);
                        4:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[4].cdf_bram_dut.ram[b]);
                        5:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[5].cdf_bram_dut.ram[b]);
                        6:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[6].cdf_bram_dut.ram[b]);
                        7:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[7].cdf_bram_dut.ram[b]);
                        8:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[8].cdf_bram_dut.ram[b]);
                        9:  for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[9].cdf_bram_dut.ram[b]);
                        10: for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[10].cdf_bram_dut.ram[b]);
                        11: for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[11].cdf_bram_dut.ram[b]);
                        12: for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[12].cdf_bram_dut.ram[b]);
                        13: for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[13].cdf_bram_dut.ram[b]);
                        14: for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[14].cdf_bram_dut.ram[b]);
                        15: for(b=0;b<256;b=b+1) $fdisplay(cdf_file_id,"%d",u_dut.CDF_BRAM_ARRAY[15].cdf_bram_dut.ram[b]);
                    endcase
                end
                $fclose(cdf_file_id);
                $display("[TB] CDF dump -> %0s", filename);
            end
        end
    endtask

endmodule
