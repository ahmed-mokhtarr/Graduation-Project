`timescale 1ns/1ps

module tb_zoom_in;

    // Parameters
    parameter IMG_WIDTH  = 1280;
    parameter IMG_HEIGHT = 720;

    // Signals
    logic        clk;
    logic        rst_n;
    logic [2:0]  curr_layer;
    logic        operation_start;
    logic        zoom_done;

    logic [31:0] flow_data;
    logic        flow_ready;
    logic        flow_rd_en;

    logic [31:0] zoomed_flow_out;
    logic        zoomed_tvalid;
    logic        zoomed_tready;

    // Queues for data handling
    logic [31:0] expected_q[$];
    logic [31:0] input_stream_q[$];

    // -------------------------------------------------------------------------
    // Pixel-index tracker – visible in waveform as 'pixel_tx_idx'
    // Counts every zoomed_tvalid & zoomed_tready handshake (0-based).
    // Add this signal to the wave to know which pixel is on the bus.
    // -------------------------------------------------------------------------
    integer pixel_tx_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || zoom_done)
            pixel_tx_idx <= 0;
        else if (zoomed_tvalid && zoomed_tready)
            pixel_tx_idx <= pixel_tx_idx + 1;
    end

    // Log file handle (integer)
    integer log_fd;

    // -------------------------------------------------------------------------
    // Logging task – writes to both console and file
    // -------------------------------------------------------------------------
    task automatic log(input string msg);
        $display("%s", msg);
        $fdisplay(log_fd, "%s", msg);
    endtask

    // DUT Instantiation
    zoom_in #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .curr_layer(curr_layer),
        .operation_start(operation_start),
        .zoom_done(zoom_done),
        .flow_data(flow_data),
        .flow_ready(flow_ready),
        .flow_rd_en(flow_rd_en),
        .zoomed_flow_out(zoomed_flow_out),
        .zoomed_tvalid(zoomed_tvalid),
        .zoomed_tready(zoomed_tready)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    // Include the transaction class
    `include "zoom_transaction.sv"

    // -------------------------------------------------------------------------
    // Golden Model – Pure Mathematical Calculation
    // -------------------------------------------------------------------------
    function automatic void compute_golden_model(zoom_transaction tr);
        int w = (IMG_WIDTH  / 2) >> tr.curr_layer;
        int h = (IMG_HEIGHT / 2) >> tr.curr_layer;
        
        // 2x2 Input Grid
        logic [31:0] p_00, p_01, p_10, p_11;
        logic signed [15:0] dx00, dy00, dx01, dy01, dx10, dy10, dx11, dy11;
        
        // Summation variables (18-bit to prevent overflow before division)
        logic signed [17:0] sum_dx, sum_dy;
        
        expected_q.delete();

        for (int y = 0; y < h; y++) begin
            
            // -----------------------------------------------------------------
            // Phase A: Top output row (00 and 01 pixels)
            // -----------------------------------------------------------------
            for (int x = 0; x < w; x++) begin
                // Fetch current and right pixels (pad right edge with 0)
                p_00 = tr.flow_data_arr[y * w + x];
                // p_01 = (x == w - 1) ? 32'd0 : tr.flow_data_arr[y * w + x + 1];
                p_01 = (x == w - 1) ? p_00 : tr.flow_data_arr[y * w + x + 1];
                dx00 = p_00[15:0];       dy00 = p_00[31:16];
                dx01 = p_01[15:0];       dy01 = p_01[31:16];

                // 00 pixel: current * 2
                expected_q.push_back({ dy00 <<< 1, dx00 <<< 1 });

                // 01 pixel: current + right
                sum_dx = $signed(dx00) + $signed(dx01);
                sum_dy = $signed(dy00) + $signed(dy01);
                expected_q.push_back({ sum_dy[15:0], sum_dx[15:0] });
            end

            // -----------------------------------------------------------------
            // Phase B: Bottom output row (10 and 11 pixels)
            // -----------------------------------------------------------------
            for (int x = 0; x < w; x++) begin
                // Fetch top row again
                p_00 = tr.flow_data_arr[y * w + x];
                p_01 = (x == w - 1) ? p_00 : tr.flow_data_arr[y * w + x + 1];
                
                // Fetch bottom row (if last line, duplicate the top row)
                if (y == h - 1) begin
                    p_10 = p_00;
                    p_11 = p_01;
                end else begin
                    p_10 = tr.flow_data_arr[(y + 1) * w + x];
                    p_11 = (x == w - 1) ? p_10 : tr.flow_data_arr[(y + 1) * w + x + 1];
                end

                dx00 = p_00[15:0];       dy00 = p_00[31:16];
                dx01 = p_01[15:0];       dy01 = p_01[31:16];
                dx10 = p_10[15:0];       dy10 = p_10[31:16];
                dx11 = p_11[15:0];       dy11 = p_11[31:16];

                // 10 pixel: current + bottom
                sum_dx = $signed(dx00) + $signed(dx10);
                sum_dy = $signed(dy00) + $signed(dy10);
                expected_q.push_back({ sum_dy[15:0], sum_dx[15:0] });
                
                // 11 pixel: (current + right + bottom + bottom_right) / 2
                sum_dx = $signed(dx00) + $signed(dx01) + $signed(dx10) + $signed(dx11);
                sum_dy = $signed(dy00) + $signed(dy01) + $signed(dy10) + $signed(dy11);
                expected_q.push_back({ sum_dy[16:1], sum_dx[16:1] });
            end
            
        end
    endfunction

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // FIXED: Separate declarations from assignments
        zoom_transaction tr;
        int error_count;
        int matched_count;
        int total_passed;
        int total_failed;
        int pixel_index;
        int i;
        string msg;
        
        error_count   = 0;
        matched_count = 0;
        total_passed  = 0;
        total_failed  = 0;
        pixel_index   = 0;

        // Open log file
        log_fd = $fopen("zoom_tb.log", "w");
        if (log_fd == 0) begin
            $fatal(1, "ERROR: Could not open zoom_tb.log for writing!");
        end

        // System Reset
        rst_n = 0;
        operation_start = 0;
        curr_layer = 0;
        flow_ready = 0;
        flow_data = 0;
        zoomed_tready = 0;
        
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        log("==================================================");
        log("   STARTING ZOOM_IN BILINEAR MODULE TESTBENCH     ");
        log("==================================================");

        // Run 5 random scenarios to cover layers
        for (i = 0; i < 5; i++) begin
            tr = new();
            if (!tr.randomize()) $fatal(1, "Transaction Randomization Failed!");
            tr.sample_cov(); // Collect coverage

            $sformat(msg, "\n[TEST %0d] Starting Layer %0d Configuration...", i, tr.curr_layer);
            log(msg);
            
            // Queue up the data for the driver
            input_stream_q.delete();
            foreach (tr.flow_data_arr[j]) input_stream_q.push_back(tr.flow_data_arr[j]);
            
            // Calculate what we expect to see
            compute_golden_model(tr);
            $sformat(msg, "[INFO] Expected Output Size: %0d pixels", expected_q.size());
            log(msg);

            // ----- Dump flow_data_arr to file -----
            begin
                integer fd_flow;
                fd_flow = $fopen("flow_data.txt", "w");
                if (fd_flow != 0) begin
                    $fdisplay(fd_flow, "%0d", tr.curr_layer);
                    foreach (tr.flow_data_arr[j])
                        $fdisplay(fd_flow, "%08h", tr.flow_data_arr[j]);
                    $fclose(fd_flow);
                    log("[INFO] flow_data_arr written to flow_data.txt");
                end
            end

            // ----- Dump expected_q to file -----
            begin
                integer fd_exp;
                fd_exp = $fopen("expected_q.txt", "w");
                if (fd_exp != 0) begin
                    $fdisplay(fd_exp, "%0d", tr.curr_layer);
                    foreach (expected_q[j])
                        $fdisplay(fd_exp, "%08h", expected_q[j]);
                    $fclose(fd_exp);
                    log("[INFO] expected_q written to expected_q.txt");
                end
            end

            // Reset per-test pixel index
            pixel_index = 0;

            // Initialize DUT
            curr_layer = tr.curr_layer;
            operation_start = 1;
            @(posedge clk);
            operation_start = 0;

            // Fork driver and monitor processes
            fork
                // Process 1: MRM Input Driver
                begin
                    while (input_stream_q.size() > 0) begin
                        // 10% chance to drop flow_ready to test pipeline stalling
                        if ($urandom_range(0, 100) > 90) begin
                            flow_ready <= 0;
                            @(posedge clk);
                        end else begin
                            flow_ready <= 1;
                            flow_data  <= input_stream_q[0];
                            @(posedge clk);
                            if (flow_rd_en && flow_ready) begin
                                void'(input_stream_q.pop_front());
                            end
                        end
                    end
                    flow_ready <= 0; // End of stream
                end

                // Process 2: Output AXI-Stream Monitor
                begin
                    while (expected_q.size() > 0) begin
                        // Randomly apply backpressure to downstream (BRAM window)
                        zoomed_tready <= ($urandom_range(0, 1) == 1);
                        @(posedge clk);

                        if (zoomed_tvalid && zoomed_tready) begin
                            // FIXED: Separate declaration from assignment
                            logic [31:0] expected_val;
                            logic [31:0] got_val;
                            expected_val = expected_q.pop_front();
                            got_val      = zoomed_flow_out;
                            
                            if (got_val !== expected_val) begin
                                $sformat(msg,
                                    "[FAIL ] Pixel #%0d | Expected: 0x%08h (dy=%0d, dx=%0d) | Got: 0x%08h (dy=%0d, dx=%0d) | Remaining: %0d",
                                    pixel_index,
                                    expected_val, $signed(expected_val[31:16]), $signed(expected_val[15:0]),
                                    got_val,      $signed(got_val[31:16]),      $signed(got_val[15:0]),
                                    expected_q.size());
                                log(msg);
                                // $fdisplay(log_fd, "%s", msg); // already logged above, but also echo to $error channel
                                $error("%s", msg);
                                error_count++;
                            end else begin
                                $sformat(msg,
                                    "[PASS ] Pixel #%0d | Value: 0x%08h (dy=%0d, dx=%0d)",
                                    pixel_index,
                                    got_val, $signed(got_val[31:16]), $signed(got_val[15:0]));
                                log(msg);
                                matched_count++;
                            end
                            pixel_index++;
                        end
                    end
                end

                // Process 3: Done Timeout Watchdog
                begin
                    wait(zoom_done == 1'b1);
                    log("[INFO] zoom_done flag caught successfully.");
                end
            join

            $sformat(msg, "[TEST %0d] Finished. Matches: %0d  Failures: %0d", i, matched_count, error_count);
            log(msg);
            total_passed += matched_count;
            total_failed += error_count;
            matched_count = 0;
            error_count   = 0;
            @(posedge clk);
            @(posedge clk);
        end

        // Final Report
        log("\n==================================================");
        $sformat(msg, "   TOTAL PASSED : %0d", total_passed);
        log(msg);
        $sformat(msg, "   TOTAL FAILED : %0d", total_failed);
        log(msg);
        if (total_failed == 0) begin
            log("   ALL TESTS PASSED SUCCESSFULLY! ZERO MISMATCHES.");
        end else begin
            $sformat(msg, "   TEST FAILED WITH %0d TOTAL MISMATCHES.", total_failed);
            log(msg);
        end
        log("   Coverage collected for all layer parameters.");
        log("==================================================");

        $fclose(log_fd);
        $stop;
    end

endmodule