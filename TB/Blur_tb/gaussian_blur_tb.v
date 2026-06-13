// ============================================================================
// Testbench: Centered Gaussian Blur
// ============================================================================
`timescale 1ns / 1ps

module gaussian_blur_tb;

    parameter IMG_WIDTH  = 1280;
    parameter IMG_HEIGHT = 720;
    parameter TOTAL_PIX  = IMG_WIDTH * IMG_HEIGHT;
    parameter CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;
    reg  [7:0]  s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;
    wire [7:0]  m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;

    reg [7:0] input_image  [0:TOTAL_PIX-1];
    reg [7:0] expected_out [0:TOTAL_PIX-1];
    reg [7:0] expected_cv  [0:TOTAL_PIX-1];
    reg [7:0] rtl_out      [0:TOTAL_PIX-1];

    integer in_idx, out_idx, col_in;
    integer good_cnt, mismatch_cnt, max_error, diff;
    integer good_cv_cnt, mismatch_cv_cnt, max_cv_error, cv_diff;
    integer i, out_file;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    gaussian_blur_top #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),   .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),   .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast)
    );

    // ── Output capture ──
    initial begin
        out_idx = 0; good_cnt = 0; mismatch_cnt = 0; max_error = 0;
        good_cv_cnt = 0; mismatch_cv_cnt = 0; max_cv_error = 0;
        @(posedge rst_n);

        while (out_idx < TOTAL_PIX) begin
            @(posedge clk);
            #1;
            if (m_axis_tvalid && m_axis_tready) begin
                rtl_out[out_idx] = m_axis_tdata;

                // Golden comparison (same index, no shift)
                if (m_axis_tdata > expected_out[out_idx])
                    diff = m_axis_tdata - expected_out[out_idx];
                else
                    diff = expected_out[out_idx] - m_axis_tdata;
                if (diff > max_error) max_error = diff;
                if (diff > 2) mismatch_cnt = mismatch_cnt + 1;
                else          good_cnt = good_cnt + 1;

                // OpenCV comparison (same index, no shift)
                if (m_axis_tdata > expected_cv[out_idx])
                    cv_diff = m_axis_tdata - expected_cv[out_idx];
                else
                    cv_diff = expected_cv[out_idx] - m_axis_tdata;
                if (cv_diff > max_cv_error) max_cv_error = cv_diff;
                if (cv_diff > 2) mismatch_cv_cnt = mismatch_cv_cnt + 1;
                else             good_cv_cnt = good_cv_cnt + 1;

                out_idx = out_idx + 1;
            end
        end

        // Write RTL output (natural order, no shift)
        out_file = $fopen("../data/rtl_output.hex", "w");
        if (out_file != 0) begin
            for (i = 0; i < TOTAL_PIX; i = i + 1)
                $fwrite(out_file, "%02X\n", rtl_out[i]);
            $fclose(out_file);
        end

        $display("simulation is done");
        #100;
        $finish;
    end

    // ── Stimulus ──
    initial begin
        $readmemh("../data/input_gray.hex", input_image);
        $readmemh("../data/expected_output.hex", expected_out);
        $readmemh("../data/expected_opencv.hex", expected_cv);

        rst_n = 0; s_axis_tdata = 0; s_axis_tvalid = 0;
        s_axis_tlast = 0; m_axis_tready = 1;

        repeat (10) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        col_in = 0;
        for (in_idx = 0; in_idx < TOTAL_PIX; in_idx = in_idx + 1) begin
            @(negedge clk);
            s_axis_tdata  = input_image[in_idx];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (col_in == IMG_WIDTH - 1) ? 1'b1 : 1'b0;
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
            col_in = (col_in == IMG_WIDTH - 1) ? 0 : col_in + 1;
        end

        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
    end

endmodule
