`timescale 1ns/1ps

module tb_system;

    // Parameters
    localparam IMG_WIDTH    = 1280;
    localparam IMG_HEIGHT   = 720;
    localparam MAX_FEATURES = 2048;
    localparam DX_WIDTH     = 5;
    localparam DY_WIDTH     = 5;
    localparam FEAT_W       = 64;
    localparam NUM_PIXELS   = IMG_WIDTH * IMG_HEIGHT;
    localparam CLK_PERIOD   = 10;

    // Clock & Reset
    reg clk;
    reg rst_n;

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // =========================================================================
    // Inputs to fast_system_top
    // =========================================================================
    // Pixels
    reg [7:0]   fast_tdata;
    reg         fast_tvalid;
    wire        fast_tready;
    reg         fast_tlast;
    reg         fast_tuser;

    // Optical Flow
    reg [9:0]   gf_tdata;
    reg         gf_tvalid;
    wire        gf_tready;
    reg         gf_tlast;

    // =========================================================================
    // Outputs from fast_system_top
    // =========================================================================
    wire [FEAT_W-1:0]   feat_tdata;
    wire                feat_tvalid;
    reg                 feat_tready;
    wire                feat_tlast;
    wire                frame_done_irq;
    wire [11:0]         total_feat_count;
    wire                fs_overflow;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    fast_system_top #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .MAX_FEATURES(MAX_FEATURES)
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .s_axis_pixels_tdata (fast_tdata),
        .s_axis_pixels_tvalid(fast_tvalid),
        .s_axis_pixels_tready(fast_tready),
        .s_axis_pixels_tlast (fast_tlast),
        .s_axis_pixels_tuser (fast_tuser),
        .s_axis_gf_tdata     (gf_tdata),
        .s_axis_gf_tvalid    (gf_tvalid),
        .s_axis_gf_tready    (gf_tready),
        .s_axis_gf_tlast     (gf_tlast),
        .m_axis_feat_tdata   (feat_tdata),
        .m_axis_feat_tvalid  (feat_tvalid),
        .m_axis_feat_tready  (feat_tready),
        .m_axis_feat_tlast   (feat_tlast),
        .frame_done_irq      (frame_done_irq),
        .total_feat_count    (total_feat_count),
        .fs_overflow         (fs_overflow)
    );

    // =========================================================================
    // Memory arrays for simulation data
    // =========================================================================
    reg [7:0]          pixel_mem [0:NUM_PIXELS-1];
    reg [9:0]          flow_mem  [0:NUM_PIXELS-1];
    
    // Expected results storage
    reg [FEAT_W-1:0] expected_feats [0:MAX_FEATURES-1];
    integer          expected_count;

    // Captured RTL output
    reg [FEAT_W-1:0] captured_feats [0:MAX_FEATURES-1];
    integer          cap_count;
    integer          out_fd;
    string           rtl_out_file;

    // =========================================================================
    // Tasks
    // =========================================================================
    // Load pixels
    task load_pixels(input string filename);
        begin
            $readmemh(filename, pixel_mem);
            $display("[TB] Loaded pixels from %s", filename);
        end
    endtask

    // Load optical flow
    task load_flow(input string filename);
        begin
            $readmemh(filename, flow_mem);
            $display("[TB] Loaded flow from %s", filename);
        end
    endtask

    // Load expected features
    task load_expected(input string filename);
        integer fd, cnt, i;
        reg [FEAT_W-1:0] val;
        begin
            fd = $fopen(filename, "r");
            if (fd == 0) begin
                $display("[TB] ERROR: Cannot open %0s", filename);
                $finish;
            end
            if ($fscanf(fd, "%d", cnt) != 1) begin
                $display("[TB] ERROR: Cannot read count from %0s", filename);
                $finish;
            end
            expected_count = cnt;
            for (i = 0; i < cnt; i = i + 1) begin
                if ($fscanf(fd, "%h", val) != 1) begin
                    $display("[TB] ERROR: Cannot read feature %0d from %0s", i, filename);
                    $finish;
                end
                expected_feats[i] = val;
            end
            $fclose(fd);
            $display("[TB] Loaded %0d expected features from %0s", cnt, filename);
        end
    endtask

    localparam FLUSH_ROWS = 5;
    task stream_pixels;
        integer idx, col;
        begin
            $display("[TB] Streaming %0d pixels + %0d flush rows...", NUM_PIXELS, FLUSH_ROWS);
            fast_tuser = 1'b1;   
            for (idx = 0; idx < NUM_PIXELS; idx = idx + 1) begin
                @(posedge clk);
                fast_tdata  = pixel_mem[idx];
                fast_tvalid = 1'b1;
                col = idx % IMG_WIDTH;
                fast_tlast  = (col == IMG_WIDTH - 1);  
                if (idx > 0) fast_tuser = 1'b0;
                while (!fast_tready) @(posedge clk);
            end
            // Flush pipeline
            for (idx = 0; idx < IMG_WIDTH * FLUSH_ROWS; idx = idx + 1) begin
                @(posedge clk);
                fast_tdata  = 8'h00;
                fast_tvalid = 1'b1;
                col = idx % IMG_WIDTH;
                fast_tlast  = (col == IMG_WIDTH - 1);
                fast_tuser  = 1'b0; 
                while (!fast_tready) @(posedge clk);
            end
            @(posedge clk);
            fast_tvalid = 1'b0;
            fast_tlast  = 1'b0;
            fast_tuser  = 1'b0;
        end
    endtask

    task stream_flow;
        integer idx;
        begin
            $display("[TB] Streaming %0d flow vectors...", NUM_PIXELS);
            for (idx = 0; idx < NUM_PIXELS; idx = idx + 1) begin
                @(posedge clk);
                gf_tdata  = flow_mem[idx];
                gf_tvalid = 1'b1;
                gf_tlast  = (idx == NUM_PIXELS - 1);
                while (!gf_tready) @(posedge clk);
            end
            @(posedge clk);
            gf_tvalid = 1'b0;
            gf_tlast  = 1'b0;
        end
    endtask

    // Monitor IRQ
    always @(posedge clk) begin
        if (frame_done_irq) begin
            $display("[TB] Received frame_done_irq! total_feat_count = %0d", total_feat_count);
        end
    end

    task capture_features;
        integer count;
        integer i;
        begin
            count = 0;
            feat_tready = 1'b1;
            while (1) begin
                @(posedge clk);
                if (feat_tvalid && feat_tready) begin
                    captured_feats[count] = feat_tdata;
                    count = count + 1;
                    if (feat_tlast) begin
                        feat_tready = 0;
                        $display("[TB] Received tlast. Captured %0d features.", count);
                        cap_count = count;

                        // Write to file
                        out_fd = $fopen(rtl_out_file, "w");
                        if (out_fd != 0) begin
                            $fdisplay(out_fd, "%0d", cap_count);
                            for (i = 0; i < cap_count; i = i + 1) begin
                                $fdisplay(out_fd, "%016x", captured_feats[i]);
                            end
                            $fclose(out_fd);
                        end else begin
                            $display("[TB] Warning: Could not write to %s", rtl_out_file);
                        end
                        disable capture_features;
                    end
                end
                if (frame_done_irq && !feat_tvalid) begin
                    $display("[TB] frame_done_irq triggered. Captured so far: %0d", count);
                    cap_count = count;
                    feat_tready = 0;
                    disable capture_features;
                end
            end
        end
    endtask

    task compare_features;
        integer i, match_count, err_count;
        begin
            match_count = 0;
            err_count = 0;
            $display("======================================================");
            $display("Comparing Expected vs Captured Features");
            $display("Expected: %0d, Captured: %0d", expected_count, cap_count);
            $display("======================================================");
            
            if (expected_count != cap_count) begin
                $display("FAIL: Count mismatch!");
            end else begin
                for (i = 0; i < cap_count; i = i + 1) begin
                    if (expected_feats[i] !== captured_feats[i]) begin
                        if (err_count < 10) begin
                            $display("Mismatch at idx %0d: Exp=%h, Cap=%h", i, expected_feats[i], captured_feats[i]);
                        end
                        err_count = err_count + 1;
                    end else begin
                        match_count = match_count + 1;
                    end
                end
                if (err_count == 0)
                    $display("SUCCESS: All %0d features matched perfectly!", expected_count);
                else
                    $display("FAIL: %0d mismatches found.", err_count);
            end
            $display("======================================================");
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    integer frame_idx;
    string pixel_file;
    string flow_file;
    string exp_file;

    initial begin
        // Initialize
        fast_tdata  = 0; fast_tvalid = 0; fast_tlast = 0; fast_tuser = 0;
        gf_tdata    = 0; gf_tvalid   = 0; gf_tlast   = 0;
        feat_tready = 0;
        rst_n       = 0;

        $display("======================================================");
        $display("[TB] FAST System Top Verification Testbench");
        $display("======================================================");

        // Reset
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        for (frame_idx = 0; frame_idx < 10; frame_idx = frame_idx + 1) begin
            $display("\n======================================================");
            $display("[TB] Processing Frame %0d", frame_idx);
            $display("======================================================");

            $sformat(pixel_file, "sim_data/frame_%0d_pixels.hex", frame_idx);
            $sformat(flow_file, "sim_data/frame_%0d_flow.hex", frame_idx);
            $sformat(exp_file, "sim_data/frame_%0d_features.hex", frame_idx);
            $sformat(rtl_out_file, "sim_output/frame_%0d_features.hex", frame_idx);

            // Load files
            load_pixels(pixel_file);
            load_flow(flow_file);
            load_expected(exp_file);

            // Run Frame
            fork
                stream_pixels;
                stream_flow;
            join
            
            // Wait for frame processing to complete
            $display("[TB] Streaming done for Frame %0d. Waiting for feature output...", frame_idx);
            capture_features;

            // Verify
            compare_features;
            
            // Add some idle cycles between frames
            #(CLK_PERIOD * 50);
        end

        // End Simulation
        $display("\n======================================================");
        $display("[TB] Simulation Complete.");
        $display("======================================================");
        #(CLK_PERIOD * 100);
        $finish;
    end

    initial begin
        while(1) begin
            @(posedge clk);
            if (u_dut.u_tracking.sort_done) begin : dump_block
                integer i;
                $display("=== INIT_SORTER DONE, DUMPING BRAMS (Frame %0d) ===", frame_idx);
                $display("=== BANK 0 DUMP (First 10) ===");
                for (i=0; i<10; i=i+1) $display("B0[%0d] = %h", i, u_dut.u_tracking.u_flist_bank0.ram[i]);
                $display("=== BANK 1 DUMP (First 10) ===");
                for (i=0; i<10; i=i+1) $display("B1[%0d] = %h", i, u_dut.u_tracking.u_flist_bank1.ram[i]);
                $display("======================================================");
            end
        end
    end


    // Timeout
    initial begin
        #(CLK_PERIOD * 200_000_000);  // 200M cycles
        $display("[TB] FATAL: Timeout!");
        $finish;
    end

endmodule
