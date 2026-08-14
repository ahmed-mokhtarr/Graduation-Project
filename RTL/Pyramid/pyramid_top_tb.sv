`timescale 1ns / 1ps

module pyramid_top_tb();

    reg clk;
    reg rst_n;

    reg  [7:0] s_axis_tdata;
    reg        s_axis_tvalid;
    wire       s_axis_tready;
    reg        s_axis_tuser;
    reg        s_axis_tlast;

    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    reg         m_axi_awready;

    wire [31:0] m_axi_wdata; 
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;

    reg         m_axi_bvalid;
    wire        m_axi_bready;
    reg  [1:0]  m_axi_bresp;

    reg  [31:0] slot_addr_0;
    reg  [31:0] slot_addr_1;
    reg  [31:0] slot_addr_2;
    reg  [31:0] slot_addr_3;

    wire        write_valid;
    wire [1:0]  frame_num;

    reg [7:0] image_data [0:3686399]; 

    pyramid_top dut (
        .clk(clk),
        .rst_n(rst_n),

        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tuser(s_axis_tuser),
        .s_axis_tlast(s_axis_tlast),

        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_bresp(m_axi_bresp),

        .slot_addr_0(slot_addr_0),
        .slot_addr_1(slot_addr_1),
        .slot_addr_2(slot_addr_2),
        .slot_addr_3(slot_addr_3),

        .write_valid(write_valid),
        .frame_num(frame_num)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    always @(negedge clk) begin
        if (!rst_n) begin
            m_axi_awready = 1'b1; 
            m_axi_wready  = 1'b1; 
            m_axi_bvalid  = 1'b0;
            m_axi_bresp   = 2'b00; 
        end else begin
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                m_axi_bvalid = 1'b1;
            end else if (m_axi_bready && m_axi_bvalid) begin
                m_axi_bvalid = 1'b0; 
            end
        end
    end

    task send_720p_frame(input integer frame_idx);
        integer x, y, pixel_idx;
        begin
            pixel_idx = frame_idx * 921600;
            for (y = 0; y < 720; y = y + 1) begin
                
                if (y % 100 == 0) begin
                    $display("[%0t]   -> Processing Row %0d / 720...", $time, y);
                end

                for (x = 0; x < 1280; x = x + 1) begin
                    
                    s_axis_tvalid = 1'b1;
                    s_axis_tdata  = image_data[pixel_idx]; 
                    s_axis_tuser  = (x == 0 && y == 0) ? 1'b1 : 1'b0;
                    s_axis_tlast  = (x == 1279) ? 1'b1 : 1'b0;
                    
                    // The Cycle-Accurate Handshake Fix
                    @(posedge clk);
                    while (s_axis_tready !== 1'b1) begin
                        @(posedge clk);
                    end
                    @(negedge clk);

                    pixel_idx = pixel_idx + 1;
                end
            end
            
            s_axis_tvalid = 1'b0;
            s_axis_tuser  = 1'b0;
            s_axis_tlast  = 1'b0;
            
            $display("[%0t]   -> Finished pushing all pixels to DUT. Waiting for DDR flush...", $time);
        end
    endtask

    reg [7:0] ddr_mock_memory [0:4910399]; 
    reg [31:0] active_write_addr;

    integer i;
    initial begin
        for (i = 0; i < 4910400; i = i + 1) begin
            ddr_mock_memory[i] = 8'h00;
        end
    end

    always @(negedge clk) begin
        if (rst_n) begin
            if (m_axi_awvalid && m_axi_awready) begin
                if (m_axi_awaddr[31:28] == 4'h4)
                    active_write_addr = (m_axi_awaddr - slot_addr_3) + 3 * 1227600;
                else if (m_axi_awaddr[31:28] == 4'h3)
                    active_write_addr = (m_axi_awaddr - slot_addr_2) + 2 * 1227600;
                else if (m_axi_awaddr[31:28] == 4'h2)
                    active_write_addr = (m_axi_awaddr - slot_addr_1) + 1 * 1227600;
                else
                    active_write_addr = (m_axi_awaddr - slot_addr_0);
            end
            
            // Extract the 4 packed bytes out of the 32-bit word
            if (m_axi_wvalid && m_axi_wready) begin
                ddr_mock_memory[active_write_addr]     = m_axi_wdata[7:0];
                ddr_mock_memory[active_write_addr + 1] = m_axi_wdata[15:8];
                ddr_mock_memory[active_write_addr + 2] = m_axi_wdata[23:16];
                ddr_mock_memory[active_write_addr + 3] = m_axi_wdata[31:24];
                active_write_addr = active_write_addr + 4;
            end
        end
    end

    integer output_file;
    integer mem_idx, f;

    initial begin
        $display("[%0t] Loading images_all_hex.txt into memory...", $time);
        $readmemh("images_all_hex.txt", image_data);

        @(negedge clk);
        rst_n = 0;
        s_axis_tvalid = 0;
        s_axis_tdata  = 0;
        s_axis_tuser  = 0;
        s_axis_tlast  = 0;

        slot_addr_0 = 32'h1000_0000;
        slot_addr_1 = 32'h2000_0000;
        slot_addr_2 = 32'h3000_0000;
        slot_addr_3 = 32'h4000_0000;

        #100;
        @(negedge clk);
        rst_n = 1;

        for (f = 0; f < 4; f = f + 1) begin
            $display("[%0t] Starting Frame %0d Transmission...", $time, f);
            send_720p_frame(f);

            wait(write_valid === 1'b1);
            $display("[%0t] Frame %0d Written to DDR. TAU Notified for Slot: %0d", $time, f, frame_num);

            #500; 
        end

        for (f = 0; f < 4; f = f + 1) begin
            $display("[%0t] Exporting memory to rtl_output_%0d.txt...", $time, f);
            output_file = $fopen($sformatf("rtl_output_%0d.txt", f), "w");
            if (output_file == 0) begin
                $display("ERROR: Could not open rtl_output_%0d.txt for writing.", f);
                $stop;
            end
            
            for (mem_idx = 0; mem_idx < 1227600; mem_idx = mem_idx + 1) begin
                $fdisplay(output_file, "%0d", ddr_mock_memory[f*1227600 + mem_idx]);
            end
            
            $fclose(output_file);
        end
        $display("[%0t] Export Complete. You can now run the Python verification.", $time);
        
        $display("[%0t] Simulation Complete.", $time);
        $stop;
    end

endmodule