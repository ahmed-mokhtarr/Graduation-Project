`timescale 1ns / 1ps
// =============================================================================
// gf_top_tb.sv  —  GF_TOP Full System Testbench (v2)
//
// Verifies the complete GF optical flow system:
//   TAU → 2×SPU → Gating Unit
//
// Fixes:
//   - Correct frame-to-memory mapping (curr→FRAME1, prev→FRAME0)
//   - Dumps ALL layer outputs (L4–L0) from DDR + gating unit
//   - Extensive debug statements for simulation visibility
// =============================================================================
module gf_top_tb();

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam MAX_W  = 1280;
    localparam MAX_H  = 720;
    localparam MAX_PX = MAX_W * MAX_H;
    localparam AXI_DATA_WIDTH = 64;
    localparam AXI_ADDR_WIDTH = 32;

    // SPU1 memory bases
    localparam SPU1_FRAME0_BASE = 32'h1000_0000;
    localparam SPU1_FRAME1_BASE = 32'h2000_0000;
    localparam SPU1_FLOW_BASE   = 32'h5000_0000;

    // SPU2 memory bases
    localparam SPU2_FRAME0_BASE = 32'h3000_0000;
    localparam SPU2_FRAME1_BASE = 32'h4000_0000;
    localparam SPU2_FLOW_BASE   = 32'h6000_0000;

    // Flow offset constants (matching mwm_acu.v addressing)
    localparam BYTES_PER_FLOW = 2;
    localparam FLOW_OFF_L0 = 0;
    localparam FLOW_OFF_L1 = FLOW_OFF_L0 + (1280 * 720 * BYTES_PER_FLOW);
    localparam FLOW_OFF_L2 = FLOW_OFF_L1 + (640 * 360 * BYTES_PER_FLOW);
    localparam FLOW_OFF_L3 = FLOW_OFF_L2 + (320 * 180 * BYTES_PER_FLOW);
    localparam FLOW_OFF_L4 = FLOW_OFF_L3 + (160 * 90 * BYTES_PER_FLOW);

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic clk;
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    logic rst_n;

    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic       write_valid;
    logic [1:0] frame_num;

    wire        gf_valid;
    wire [15:0] gf_flow;
    wire        overflow_flag;
    wire        idle_spu1, idle_spu2;

    // --- SPU1 AXI ---
    wire [AXI_ADDR_WIDTH-1:0] s1_curr_araddr;  wire [7:0] s1_curr_arlen;
    wire [2:0] s1_curr_arsize; wire [1:0] s1_curr_arburst; wire s1_curr_arvalid;
    logic s1_curr_arready; logic [AXI_DATA_WIDTH-1:0] s1_curr_rdata;
    logic s1_curr_rlast, s1_curr_rvalid; wire s1_curr_rready;

    wire [AXI_ADDR_WIDTH-1:0] s1_prev_araddr;  wire [7:0] s1_prev_arlen;
    wire [2:0] s1_prev_arsize; wire [1:0] s1_prev_arburst; wire s1_prev_arvalid;
    logic s1_prev_arready; logic [AXI_DATA_WIDTH-1:0] s1_prev_rdata;
    logic s1_prev_rlast, s1_prev_rvalid; wire s1_prev_rready;

    wire [AXI_ADDR_WIDTH-1:0] s1_flow_araddr;  wire [7:0] s1_flow_arlen;
    wire [2:0] s1_flow_arsize; wire [1:0] s1_flow_arburst; wire s1_flow_arvalid;
    logic s1_flow_arready; logic [AXI_DATA_WIDTH-1:0] s1_flow_rdata;
    logic s1_flow_rlast, s1_flow_rvalid; wire s1_flow_rready;

    wire [AXI_ADDR_WIDTH-1:0] s1_w_awaddr; wire [7:0] s1_w_awlen;
    wire [2:0] s1_w_awsize; wire [1:0] s1_w_awburst; wire s1_w_awvalid;
    logic s1_w_awready; wire [AXI_DATA_WIDTH-1:0] s1_w_wdata;
    wire [7:0] s1_w_wstrb; wire s1_w_wlast, s1_w_wvalid;
    logic s1_w_wready; logic [1:0] s1_w_bresp; logic s1_w_bvalid; wire s1_w_bready;

    // --- SPU2 AXI ---
    wire [AXI_ADDR_WIDTH-1:0] s2_curr_araddr;  wire [7:0] s2_curr_arlen;
    wire [2:0] s2_curr_arsize; wire [1:0] s2_curr_arburst; wire s2_curr_arvalid;
    logic s2_curr_arready; logic [AXI_DATA_WIDTH-1:0] s2_curr_rdata;
    logic s2_curr_rlast, s2_curr_rvalid; wire s2_curr_rready;

    wire [AXI_ADDR_WIDTH-1:0] s2_prev_araddr;  wire [7:0] s2_prev_arlen;
    wire [2:0] s2_prev_arsize; wire [1:0] s2_prev_arburst; wire s2_prev_arvalid;
    logic s2_prev_arready; logic [AXI_DATA_WIDTH-1:0] s2_prev_rdata;
    logic s2_prev_rlast, s2_prev_rvalid; wire s2_prev_rready;

    wire [AXI_ADDR_WIDTH-1:0] s2_flow_araddr;  wire [7:0] s2_flow_arlen;
    wire [2:0] s2_flow_arsize; wire [1:0] s2_flow_arburst; wire s2_flow_arvalid;
    logic s2_flow_arready; logic [AXI_DATA_WIDTH-1:0] s2_flow_rdata;
    logic s2_flow_rlast, s2_flow_rvalid; wire s2_flow_rready;

    wire [AXI_ADDR_WIDTH-1:0] s2_w_awaddr; wire [7:0] s2_w_awlen;
    wire [2:0] s2_w_awsize; wire [1:0] s2_w_awburst; wire s2_w_awvalid;
    logic s2_w_awready; wire [AXI_DATA_WIDTH-1:0] s2_w_wdata;
    wire [7:0] s2_w_wstrb; wire s2_w_wlast, s2_w_wvalid;
    logic s2_w_wready; logic [1:0] s2_w_bresp; logic s2_w_bvalid; wire s2_w_bready;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    gf_top #(
        .PIXEL_WIDTH      (8),
        .FLOW_WIDTH       (16),
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH   (AXI_ADDR_WIDTH),
        .IMG_WIDTH        (MAX_W),
        .IMG_HEIGHT       (MAX_H),
        .FIFO_DEPTH       (512),
        .FIFO_ADDR_W      (9),
        .SPU1_FRAME0_BASE (SPU1_FRAME0_BASE),
        .SPU1_FRAME1_BASE (SPU1_FRAME1_BASE),
        .SPU1_FLOW_BASE   (SPU1_FLOW_BASE),
        .SPU2_FRAME0_BASE (SPU2_FRAME0_BASE),
        .SPU2_FRAME1_BASE (SPU2_FRAME1_BASE),
        .SPU2_FLOW_BASE   (SPU2_FLOW_BASE)
    ) u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .write_valid   (write_valid),
        .frame_num     (frame_num),
        .gf_valid      (gf_valid),
        .gf_flow       (gf_flow),
        .overflow_flag (overflow_flag),
        .idle_spu1     (idle_spu1),
        .idle_spu2     (idle_spu2),
        // SPU1 AXI
        .s1_m_axi_curr_araddr(s1_curr_araddr), .s1_m_axi_curr_arlen(s1_curr_arlen),
        .s1_m_axi_curr_arsize(s1_curr_arsize), .s1_m_axi_curr_arburst(s1_curr_arburst),
        .s1_m_axi_curr_arvalid(s1_curr_arvalid), .s1_m_axi_curr_arready(s1_curr_arready),
        .s1_m_axi_curr_rdata(s1_curr_rdata), .s1_m_axi_curr_rlast(s1_curr_rlast),
        .s1_m_axi_curr_rvalid(s1_curr_rvalid), .s1_m_axi_curr_rready(s1_curr_rready),

        .s1_m_axi_prev_araddr(s1_prev_araddr), .s1_m_axi_prev_arlen(s1_prev_arlen),
        .s1_m_axi_prev_arsize(s1_prev_arsize), .s1_m_axi_prev_arburst(s1_prev_arburst),
        .s1_m_axi_prev_arvalid(s1_prev_arvalid), .s1_m_axi_prev_arready(s1_prev_arready),
        .s1_m_axi_prev_rdata(s1_prev_rdata), .s1_m_axi_prev_rlast(s1_prev_rlast),
        .s1_m_axi_prev_rvalid(s1_prev_rvalid), .s1_m_axi_prev_rready(s1_prev_rready),

        .s1_m_axi_flow_araddr(s1_flow_araddr), .s1_m_axi_flow_arlen(s1_flow_arlen),
        .s1_m_axi_flow_arsize(s1_flow_arsize), .s1_m_axi_flow_arburst(s1_flow_arburst),
        .s1_m_axi_flow_arvalid(s1_flow_arvalid), .s1_m_axi_flow_arready(s1_flow_arready),
        .s1_m_axi_flow_rdata(s1_flow_rdata), .s1_m_axi_flow_rlast(s1_flow_rlast),
        .s1_m_axi_flow_rvalid(s1_flow_rvalid), .s1_m_axi_flow_rready(s1_flow_rready),

        .s1_m_axi_w_awaddr(s1_w_awaddr), .s1_m_axi_w_awlen(s1_w_awlen),
        .s1_m_axi_w_awsize(s1_w_awsize), .s1_m_axi_w_awburst(s1_w_awburst),
        .s1_m_axi_w_awvalid(s1_w_awvalid), .s1_m_axi_w_awready(s1_w_awready),
        .s1_m_axi_w_wdata(s1_w_wdata), .s1_m_axi_w_wstrb(s1_w_wstrb),
        .s1_m_axi_w_wlast(s1_w_wlast), .s1_m_axi_w_wvalid(s1_w_wvalid),
        .s1_m_axi_w_wready(s1_w_wready), .s1_m_axi_w_bresp(s1_w_bresp),
        .s1_m_axi_w_bvalid(s1_w_bvalid), .s1_m_axi_w_bready(s1_w_bready),

        // SPU2 AXI
        .s2_m_axi_curr_araddr(s2_curr_araddr), .s2_m_axi_curr_arlen(s2_curr_arlen),
        .s2_m_axi_curr_arsize(s2_curr_arsize), .s2_m_axi_curr_arburst(s2_curr_arburst),
        .s2_m_axi_curr_arvalid(s2_curr_arvalid), .s2_m_axi_curr_arready(s2_curr_arready),
        .s2_m_axi_curr_rdata(s2_curr_rdata), .s2_m_axi_curr_rlast(s2_curr_rlast),
        .s2_m_axi_curr_rvalid(s2_curr_rvalid), .s2_m_axi_curr_rready(s2_curr_rready),

        .s2_m_axi_prev_araddr(s2_prev_araddr), .s2_m_axi_prev_arlen(s2_prev_arlen),
        .s2_m_axi_prev_arsize(s2_prev_arsize), .s2_m_axi_prev_arburst(s2_prev_arburst),
        .s2_m_axi_prev_arvalid(s2_prev_arvalid), .s2_m_axi_prev_arready(s2_prev_arready),
        .s2_m_axi_prev_rdata(s2_prev_rdata), .s2_m_axi_prev_rlast(s2_prev_rlast),
        .s2_m_axi_prev_rvalid(s2_prev_rvalid), .s2_m_axi_prev_rready(s2_prev_rready),

        .s2_m_axi_flow_araddr(s2_flow_araddr), .s2_m_axi_flow_arlen(s2_flow_arlen),
        .s2_m_axi_flow_arsize(s2_flow_arsize), .s2_m_axi_flow_arburst(s2_flow_arburst),
        .s2_m_axi_flow_arvalid(s2_flow_arvalid), .s2_m_axi_flow_arready(s2_flow_arready),
        .s2_m_axi_flow_rdata(s2_flow_rdata), .s2_m_axi_flow_rlast(s2_flow_rlast),
        .s2_m_axi_flow_rvalid(s2_flow_rvalid), .s2_m_axi_flow_rready(s2_flow_rready),

        .s2_m_axi_w_awaddr(s2_w_awaddr), .s2_m_axi_w_awlen(s2_w_awlen),
        .s2_m_axi_w_awsize(s2_w_awsize), .s2_m_axi_w_awburst(s2_w_awburst),
        .s2_m_axi_w_awvalid(s2_w_awvalid), .s2_m_axi_w_awready(s2_w_awready),
        .s2_m_axi_w_wdata(s2_w_wdata), .s2_m_axi_w_wstrb(s2_w_wstrb),
        .s2_m_axi_w_wlast(s2_w_wlast), .s2_m_axi_w_wvalid(s2_w_wvalid),
        .s2_m_axi_w_wready(s2_w_wready), .s2_m_axi_w_bresp(s2_w_bresp),
        .s2_m_axi_w_bvalid(s2_w_bvalid), .s2_m_axi_w_bready(s2_w_bready)
    );

    // =========================================================================
    // Unified Memory Model
    // =========================================================================
    reg [7:0] mem_spu1_f0 [0:32'h1FFFFF]; // SPU1 Frame0 (2MB)
    reg [7:0] mem_spu1_f1 [0:32'h1FFFFF]; // SPU1 Frame1 (2MB)
    reg [7:0] mem_spu1_fl [0:32'h3FFFFF]; // SPU1 Flow   (4MB)
    reg [7:0] mem_spu2_f0 [0:32'h1FFFFF]; // SPU2 Frame0 (2MB)
    reg [7:0] mem_spu2_f1 [0:32'h1FFFFF]; // SPU2 Frame1 (2MB)
    reg [7:0] mem_spu2_fl [0:32'h3FFFFF]; // SPU2 Flow   (4MB)

    function void write_byte(input [31:0] addr, input [7:0] data);
        if      (addr >= SPU1_FRAME0_BASE && addr < SPU1_FRAME0_BASE + 32'h200000)
            mem_spu1_f0[addr - SPU1_FRAME0_BASE] = data;
        else if (addr >= SPU1_FRAME1_BASE && addr < SPU1_FRAME1_BASE + 32'h200000)
            mem_spu1_f1[addr - SPU1_FRAME1_BASE] = data;
        else if (addr >= SPU1_FLOW_BASE && addr < SPU1_FLOW_BASE + 32'h400000)
            mem_spu1_fl[addr - SPU1_FLOW_BASE] = data;
        else if (addr >= SPU2_FRAME0_BASE && addr < SPU2_FRAME0_BASE + 32'h200000)
            mem_spu2_f0[addr - SPU2_FRAME0_BASE] = data;
        else if (addr >= SPU2_FRAME1_BASE && addr < SPU2_FRAME1_BASE + 32'h200000)
            mem_spu2_f1[addr - SPU2_FRAME1_BASE] = data;
        else if (addr >= SPU2_FLOW_BASE && addr < SPU2_FLOW_BASE + 32'h400000)
            mem_spu2_fl[addr - SPU2_FLOW_BASE] = data;
    endfunction

    function logic [7:0] read_byte(input [31:0] addr);
        if      (addr >= SPU1_FRAME0_BASE && addr < SPU1_FRAME0_BASE + 32'h200000)
            return mem_spu1_f0[addr - SPU1_FRAME0_BASE];
        else if (addr >= SPU1_FRAME1_BASE && addr < SPU1_FRAME1_BASE + 32'h200000)
            return mem_spu1_f1[addr - SPU1_FRAME1_BASE];
        else if (addr >= SPU1_FLOW_BASE && addr < SPU1_FLOW_BASE + 32'h400000)
            return mem_spu1_fl[addr - SPU1_FLOW_BASE];
        else if (addr >= SPU2_FRAME0_BASE && addr < SPU2_FRAME0_BASE + 32'h200000)
            return mem_spu2_f0[addr - SPU2_FRAME0_BASE];
        else if (addr >= SPU2_FRAME1_BASE && addr < SPU2_FRAME1_BASE + 32'h200000)
            return mem_spu2_f1[addr - SPU2_FRAME1_BASE];
        else if (addr >= SPU2_FLOW_BASE && addr < SPU2_FLOW_BASE + 32'h400000)
            return mem_spu2_fl[addr - SPU2_FLOW_BASE];
        else return 8'h00;
    endfunction

    // =========================================================================
    // AXI Write Slave — SPU1
    // =========================================================================
    reg [AXI_ADDR_WIDTH-1:0] s1_aw_addr_l;
    reg [7:0] s1_aw_len_l, s1_w_beat_cnt;
    reg       s1_aw_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_w_awready <= 0; s1_w_wready <= 0; s1_w_bvalid <= 0;
            s1_w_bresp <= 0; s1_aw_addr_l <= 0; s1_aw_len_l <= 0;
            s1_aw_pending <= 0; s1_w_beat_cnt <= 0;
        end else begin
            s1_w_awready <= 1'b0;
            if (s1_w_awvalid && !s1_aw_pending) begin
                s1_w_awready <= 1; s1_aw_addr_l <= s1_w_awaddr;
                s1_aw_len_l <= s1_w_awlen; s1_aw_pending <= 1; s1_w_beat_cnt <= 0;
            end
            if (s1_aw_pending && !s1_w_bvalid) s1_w_wready <= 1;
            else s1_w_wready <= 0;
            if (s1_w_wvalid && s1_w_wready && s1_aw_pending) begin
                automatic logic [31:0] a = s1_aw_addr_l + (s1_w_beat_cnt * 8);
                for (int b=0; b<8; b++) write_byte(a+b, s1_w_wdata[b*8+:8]);
                s1_w_beat_cnt <= s1_w_beat_cnt + 1;
                if (s1_w_wlast) begin
                    s1_w_bvalid <= 1; s1_w_bresp <= 0;
                    s1_aw_pending <= 0; s1_w_wready <= 0;
                end
            end
            if (s1_w_bvalid && s1_w_bready) s1_w_bvalid <= 0;
        end
    end

    // =========================================================================
    // AXI Write Slave — SPU2
    // =========================================================================
    reg [AXI_ADDR_WIDTH-1:0] s2_aw_addr_l;
    reg [7:0] s2_aw_len_l, s2_w_beat_cnt;
    reg       s2_aw_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_w_awready <= 0; s2_w_wready <= 0; s2_w_bvalid <= 0;
            s2_w_bresp <= 0; s2_aw_addr_l <= 0; s2_aw_len_l <= 0;
            s2_aw_pending <= 0; s2_w_beat_cnt <= 0;
        end else begin
            s2_w_awready <= 1'b0;
            if (s2_w_awvalid && !s2_aw_pending) begin
                s2_w_awready <= 1; s2_aw_addr_l <= s2_w_awaddr;
                s2_aw_len_l <= s2_w_awlen; s2_aw_pending <= 1; s2_w_beat_cnt <= 0;
            end
            if (s2_aw_pending && !s2_w_bvalid) s2_w_wready <= 1;
            else s2_w_wready <= 0;
            if (s2_w_wvalid && s2_w_wready && s2_aw_pending) begin
                automatic logic [31:0] a = s2_aw_addr_l + (s2_w_beat_cnt * 8);
                for (int b=0; b<8; b++) write_byte(a+b, s2_w_wdata[b*8+:8]);
                s2_w_beat_cnt <= s2_w_beat_cnt + 1;
                if (s2_w_wlast) begin
                    s2_w_bvalid <= 1; s2_w_bresp <= 0;
                    s2_aw_pending <= 0; s2_w_wready <= 0;
                end
            end
            if (s2_w_bvalid && s2_w_bready) s2_w_bvalid <= 0;
        end
    end

    // =========================================================================
    // AXI Read Slaves (6 instances: 3 per SPU)
    // =========================================================================
    axi_read_slave #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH)) s1_rd_curr (
        .clk(clk), .araddr(s1_curr_araddr), .arlen(s1_curr_arlen),
        .arvalid(s1_curr_arvalid), .arready(s1_curr_arready),
        .rdata(s1_curr_rdata), .rlast(s1_curr_rlast), .rvalid(s1_curr_rvalid), .rready(s1_curr_rready)
    );
    axi_read_slave #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH)) s1_rd_prev (
        .clk(clk), .araddr(s1_prev_araddr), .arlen(s1_prev_arlen),
        .arvalid(s1_prev_arvalid), .arready(s1_prev_arready),
        .rdata(s1_prev_rdata), .rlast(s1_prev_rlast), .rvalid(s1_prev_rvalid), .rready(s1_prev_rready)
    );
    axi_read_slave #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH)) s1_rd_flow (
        .clk(clk), .araddr(s1_flow_araddr), .arlen(s1_flow_arlen),
        .arvalid(s1_flow_arvalid), .arready(s1_flow_arready),
        .rdata(s1_flow_rdata), .rlast(s1_flow_rlast), .rvalid(s1_flow_rvalid), .rready(s1_flow_rready)
    );
    axi_read_slave #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH)) s2_rd_curr (
        .clk(clk), .araddr(s2_curr_araddr), .arlen(s2_curr_arlen),
        .arvalid(s2_curr_arvalid), .arready(s2_curr_arready),
        .rdata(s2_curr_rdata), .rlast(s2_curr_rlast), .rvalid(s2_curr_rvalid), .rready(s2_curr_rready)
    );
    axi_read_slave #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH)) s2_rd_prev (
        .clk(clk), .araddr(s2_prev_araddr), .arlen(s2_prev_arlen),
        .arvalid(s2_prev_arvalid), .arready(s2_prev_arready),
        .rdata(s2_prev_rdata), .rlast(s2_prev_rlast), .rvalid(s2_prev_rvalid), .rready(s2_prev_rready)
    );
    axi_read_slave #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH)) s2_rd_flow (
        .clk(clk), .araddr(s2_flow_araddr), .arlen(s2_flow_arlen),
        .arvalid(s2_flow_arvalid), .arready(s2_flow_arready),
        .rdata(s2_flow_rdata), .rlast(s2_flow_rlast), .rvalid(s2_flow_rvalid), .rready(s2_flow_rready)
    );

    // =========================================================================
    // Output Capture — Gating Unit L0 flow
    // =========================================================================
    logic [15:0] gf_out_mem [0:MAX_PX-1];
    int          gf_out_count;

    wire [2:0] spu1_layer = u_dut.u_spu1.current_layer;

    always @(posedge clk) begin
        if (gf_valid) begin
            gf_out_mem[gf_out_count] <= gf_flow;
            gf_out_count <= gf_out_count + 1;
        end
    end

    // Pulse Counters
    int cnt_poly_exp = 0;
    int cnt_cbw = 0;
    int cnt_gf_valid = 0;
    int update_flow_vfilt = 0;
    int update_flow_hfilt = 0;
    int update_flow_valid = 0;

    always @(posedge clk) begin
        if (rst_n && u_dut.u_spu1.current_layer == 3'd0) begin
            if (u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_mapped_cg.u_coef_gen.u_poly_curr.valid_out)
                cnt_poly_exp <= cnt_poly_exp + 1;
            
            if (u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_mapped_cg.u_cbw.valid_out)
                cnt_cbw <= cnt_cbw + 1;

            if (u_dut.u_gu.gf_valid)
                cnt_gf_valid <= cnt_gf_valid + 1;
                
            if (u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_update_top.u_flow.v_valid)
                update_flow_vfilt <= update_flow_vfilt + 1;

            if (u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_update_top.u_flow.h_valid)
                update_flow_hfilt <= update_flow_hfilt + 1;

            if (u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_update_top.u_flow.valid_out)
                update_flow_valid <= update_flow_valid + 1;
        end
    end

    // =========================================================================
    // DEBUG: Monitor internal SPU1 layer transitions
    // =========================================================================
    wire [2:0] spu2_layer = u_dut.u_spu2.current_layer;
    wire       spu1_op_start = u_dut.u_spu1.u_fsm.operation_start;
    wire       spu1_layer_done = u_dut.u_spu1.layer_done;
    wire       spu1_mwm_done = u_dut.u_spu1.mwm_layer_done;
    wire       spu1_frame_done = u_dut.u_spu1.pipeline_frame_done;
    wire [1:0] tau_state = u_dut.u_tau.current_state;

    logic [2:0] prev_spu1_layer;
    logic       prev_spu1_op_start;

    always @(posedge clk) begin
        prev_spu1_layer <= spu1_layer;
        prev_spu1_op_start <= spu1_op_start;

        // Detect operation_start pulse
        if (spu1_op_start && !prev_spu1_op_start)
            $display("[DBG %0t] SPU1 operation_start PULSE → Layer %0d", $time, spu1_layer);

        // Detect layer transitions
        if (spu1_layer != prev_spu1_layer && !idle_spu1)
            $display("[DBG %0t] SPU1 layer transition: L%0d → L%0d", $time, prev_spu1_layer, spu1_layer);

        // Detect mwm_layer_done — dump that layer's DDR flow immediately
        if (spu1_mwm_done) begin
            $display("[DBG %0t] SPU1 mwm_layer_done asserted (layer=%0d)", $time, spu1_layer);
            dump_flow_layer_from_ddr(SPU1_FLOW_BASE, spu1_layer);
        end

        // Detect pipeline_frame_done
        if (spu1_frame_done)
            $display("[DBG %0t] SPU1 pipeline_frame_done asserted (layer=%0d)", $time, spu1_layer);
    end

    // =========================================================================
    // DEBUG: Deep pipeline instrumentation for L1 hang diagnosis
    // =========================================================================
    // Hierarchical references into SPU1 pipeline
    wire [3:0] dbg_zi_state   = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_zoom_in.state;
    wire       dbg_zi_ready   = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_zoom_in.zoomed_data_ready;
    wire [1:0] dbg_cbw_state  = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_mapped_cg.u_cbw.state;
    wire [10:0] dbg_cbw_xin   = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_mapped_cg.u_cbw.x_in;
    wire [10:0] dbg_cbw_yin   = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_mapped_cg.u_cbw.y_in;
    wire       dbg_cbw_tready = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_mapped_cg.u_cbw.tready;
    wire       dbg_cbw_vout   = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_mapped_cg.u_cbw.valid_out;
    wire       dbg_cbw_sampling = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_mapped_cg.cbw_sampling;
    wire       dbg_data_ready = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.data_ready;
    wire       dbg_flow_ready = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.flow_ready;
    wire       dbg_ready      = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.ready;
    wire       dbg_gf_vout    = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.gf_valid_out;
    wire       dbg_pipe_vout  = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.valid_out;
    wire       dbg_skip_zoom  = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.skip_zoom;
    wire [1:0] dbg_rgi_state  = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_rgi.state;
    wire [12:0] dbg_rgi_cnt   = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_rgi.fifo_count;
    wire       dbg_rgi_vout   = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_rgi.valid_out;
    wire       dbg_mcg_valid  = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.mcg_valid;
    wire       dbg_gf_gated_dr = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.gf_gated_data_ready;

    // Counters for tracking throughput
    int dbg_cbw_sample_cnt, dbg_gf_vout_cnt, dbg_pipe_vout_cnt, dbg_mcg_valid_cnt;
    int dbg_last_sample_time;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_cbw_sample_cnt <= 0;
            dbg_gf_vout_cnt    <= 0;
            dbg_pipe_vout_cnt  <= 0;
            dbg_mcg_valid_cnt  <= 0;
            dbg_last_sample_time <= 0;
        end else begin
            if (spu1_layer != prev_spu1_layer) begin
                // Reset counters on layer change
                dbg_cbw_sample_cnt <= 0;
                dbg_gf_vout_cnt    <= 0;
                dbg_pipe_vout_cnt  <= 0;
                dbg_mcg_valid_cnt  <= 0;
                dbg_last_sample_time <= $time;
            end else begin
                if (dbg_cbw_sampling) dbg_cbw_sample_cnt <= dbg_cbw_sample_cnt + 1;
                if (dbg_gf_vout)     dbg_gf_vout_cnt    <= dbg_gf_vout_cnt + 1;
                if (dbg_pipe_vout)   dbg_pipe_vout_cnt  <= dbg_pipe_vout_cnt + 1;
                if (dbg_mcg_valid)   dbg_mcg_valid_cnt  <= dbg_mcg_valid_cnt + 1;
            end
        end
    end

    // MRM-level debug probes
    wire [1:0]  dbg_axi_curr_st = u_dut.u_spu1.u_pipeline.u_mrm.u_axi_read_curr.state;
    wire [31:0] dbg_axi_curr_br = u_dut.u_spu1.u_pipeline.u_mrm.u_axi_read_curr.beats_read;
    wire [31:0] dbg_axi_curr_tb = u_dut.u_spu1.u_pipeline.u_mrm.u_axi_read_curr.target_beats;
    wire [1:0]  dbg_axi_prev_st = u_dut.u_spu1.u_pipeline.u_mrm.u_axi_read_prev.state;
    wire [31:0] dbg_axi_prev_br = u_dut.u_spu1.u_pipeline.u_mrm.u_axi_read_prev.beats_read;
    wire        dbg_curr_empty  = u_dut.u_spu1.u_pipeline.u_mrm.u_curr_fifo.inst.empty;
    wire        dbg_curr_full   = u_dut.u_spu1.u_pipeline.u_mrm.u_curr_fifo.inst.full;
    wire        dbg_prev_empty  = u_dut.u_spu1.u_pipeline.u_mrm.u_prev_fifo.inst.empty;
    wire        dbg_prev_full   = u_dut.u_spu1.u_pipeline.u_mrm.u_prev_fifo.inst.full;
    wire        dbg_flow_empty  = u_dut.u_spu1.u_pipeline.u_mrm.u_flow_fifo.inst.empty;
    wire [12:0] dbg_curr_cnt    = u_dut.u_spu1.u_pipeline.u_mrm.u_curr_fifo.inst.count;
    wire [12:0] dbg_prev_cnt    = u_dut.u_spu1.u_pipeline.u_mrm.u_prev_fifo.inst.count;

    // Periodic debug print during L1
    int dbg_l1_cycle_cnt;
    always @(posedge clk) begin
        if (spu1_layer == 3'd1 && !idle_spu1) begin
            dbg_l1_cycle_cnt <= dbg_l1_cycle_cnt + 1;
            // Print snapshot at 1000, 5000, 10000 cycles and then every 200k cycles
            if (dbg_l1_cycle_cnt == 1000 || dbg_l1_cycle_cnt == 5000 || 
                dbg_l1_cycle_cnt == 10000 || (dbg_l1_cycle_cnt % 200000 == 0 && dbg_l1_cycle_cnt > 0)) begin
                $display("[L1_DBG %0t cyc=%0d] zi_st=%0d zi_rdy=%b | cbw_st=%0d x=%0d y=%0d tready=%b vout=%b | dr=%b fr=%b rdy=%b gated_dr=%b | skip=%b",
                    $time, dbg_l1_cycle_cnt,
                    dbg_zi_state, dbg_zi_ready,
                    dbg_cbw_state, dbg_cbw_xin, dbg_cbw_yin, dbg_cbw_tready, dbg_cbw_vout,
                    dbg_data_ready, dbg_flow_ready, dbg_ready, dbg_gf_gated_dr,
                    dbg_skip_zoom);
                $display("[L1_DBG %0t cyc=%0d] rgi_st=%0d rgi_cnt=%0d rgi_vo=%b | mcg_v=%b gf_vo=%b pipe_vo=%b | samples=%0d gf_outs=%0d pipe_outs=%0d mcg_outs=%0d",
                    $time, dbg_l1_cycle_cnt,
                    dbg_rgi_state, dbg_rgi_cnt, dbg_rgi_vout,
                    dbg_mcg_valid, dbg_gf_vout, dbg_pipe_vout,
                    dbg_cbw_sample_cnt, dbg_gf_vout_cnt, dbg_pipe_vout_cnt, dbg_mcg_valid_cnt);
                $display("[L1_MRM %0t cyc=%0d] curr_axi: st=%0d br=%0d/%0d | prev_axi: st=%0d br=%0d | curr_fifo: e=%b f=%b cnt=%0d | prev_fifo: e=%b f=%b cnt=%0d | flow_e=%b",
                    $time, dbg_l1_cycle_cnt,
                    dbg_axi_curr_st, dbg_axi_curr_br, dbg_axi_curr_tb,
                    dbg_axi_prev_st, dbg_axi_prev_br,
                    dbg_curr_empty, dbg_curr_full, dbg_curr_cnt,
                    dbg_prev_empty, dbg_prev_full, dbg_prev_cnt,
                    dbg_flow_empty);
            end
        end else begin
            dbg_l1_cycle_cnt <= 0;
        end
    end

    wire [2:0]  dbg_mwm_state = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_mwm.wc_state;
    wire [9:0]  dbg_mwm_fifo  = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_mwm.fifo_count;
    wire [31:0] dbg_mwm_px    = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_mwm.pixel_count;
    wire        dbg_mwm_all_rx= u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_mwm.all_pixels_received;
    wire [1:0]  dbg_mwm_pack  = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_mwm.pack_cnt;
    wire [2:0]  dbg_mwm_axi_st = u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_mwm.u_axi_write.state;

    int dbg_l4_cycle_cnt;
    always @(posedge clk) begin
        if (spu1_layer == 3'd4 && !idle_spu1) begin
            dbg_l4_cycle_cnt <= dbg_l4_cycle_cnt + 1;
            if (dbg_l4_cycle_cnt > 5000 && dbg_l4_cycle_cnt % 500 == 0) begin
                $display("[L4_MWM %0t cyc=%0d] st=%0d fifo=%0d px=%0d all=%b pack=%0d axi_st=%0d",
                    $time, dbg_l4_cycle_cnt, dbg_mwm_state, dbg_mwm_fifo, dbg_mwm_px, dbg_mwm_all_rx, dbg_mwm_pack, dbg_mwm_axi_st);
            end
        end else begin
            dbg_l4_cycle_cnt <= 0;
        end
    end

    // =========================================================================
    // Tasks: Memory Loading
    // =========================================================================
    task automatic load_layer_images(input [31:0] frame0_base, input [31:0] frame1_base, input int lnum);
        string fn;
        logic [7:0] temp_img [0:MAX_PX-1];
        int w, h, offset;

        case (lnum)
            4: begin w = 80;   h = 45;  offset = (1280*720) + (640*360) + (320*180) + (160*90); end
            3: begin w = 160;  h = 90;  offset = (1280*720) + (640*360) + (320*180); end
            2: begin w = 320;  h = 180; offset = (1280*720) + (640*360); end
            1: begin w = 640;  h = 360; offset = (1280*720); end
            0: begin w = 1280; h = 720; offset = 0; end
        endcase

        // IMPORTANT: frame_num mapping through TAU + FSM + MRM_ACU:
        //   TAU sends spu1_frames = {frame_i=1, frame_i_minus_1=0}
        //   FSM: curr_frame_idx = frames[3:2] = 1  → reads from FRAME1_BASE
        //        prev_frame_idx = frames[1:0] = 0  → reads from FRAME0_BASE
        //
        // So: curr_L*.hex → FRAME1_BASE, prev_L*.hex → FRAME0_BASE

        // Previous frame → FRAME0_BASE (prev_frame_idx=0 reads from here)
        fn = $sformatf("../../../golden_data/pyramid_frame0_L%0d.hex", lnum);
        $readmemh(fn, temp_img);
        for(int i=0; i<w*h; i++) write_byte(frame0_base + offset + i, temp_img[i]);

        // Current frame → FRAME1_BASE (curr_frame_idx=1 reads from here)
        fn = $sformatf("../../../golden_data/pyramid_frame1_L%0d.hex", lnum);
        $readmemh(fn, temp_img);
        for(int i=0; i<w*h; i++) write_byte(frame1_base + offset + i, temp_img[i]);

        $display("[TB] Loaded L%0d (%0dx%0d): prev→Frame0(0x%08h), curr→Frame1(0x%08h)",
                 lnum, w, h, frame0_base, frame1_base);
    endtask

    // =========================================================================
    // Tasks: Output Dump — All Layers
    // =========================================================================
    task automatic dump_flow_layer_from_ddr(input [31:0] flow_base, input int lnum);
        string fn;
        integer fd;
        int w, h;
        int flow_offset;
        reg signed [7:0] dx_s, dy_s;

        case (lnum)
            4: begin w = 80;   h = 45;  flow_offset = FLOW_OFF_L4; end
            3: begin w = 160;  h = 90;  flow_offset = FLOW_OFF_L3; end
            2: begin w = 320;  h = 180; flow_offset = FLOW_OFF_L2; end
            1: begin w = 640;  h = 360; flow_offset = FLOW_OFF_L1; end
            0: begin w = 1280; h = 720; flow_offset = FLOW_OFF_L0; end
        endcase

        fn = $sformatf("output/L%0d_mwm_ddr_deltas.txt", lnum);
        fd = $fopen(fn, "w");

        for(int i=0; i<w*h; i++) begin
            dx_s = $signed(read_byte(flow_base + flow_offset + i*2));
            dy_s = $signed(read_byte(flow_base + flow_offset + i*2 + 1));
            $fwrite(fd, "%0d %0d\n", dy_s, dx_s);
        end
        $fclose(fd);
        $display("[TB] Dumped L%0d DDR flow → %s (%0d pixels)", lnum, fn, w*h);
    endtask

    task automatic dump_gf_output();
        string fn;
        integer fd;
        reg signed [7:0] dx_s, dy_s;

        fn = "output/gf_top_L0_deltas.txt";
        fd = $fopen(fn, "w");

        for(int i=0; i<gf_out_count; i++) begin
            dx_s = $signed(gf_out_mem[i][7:0]);
            dy_s = $signed(gf_out_mem[i][15:8]);
            $fwrite(fd, "%0d %0d\n", dy_s, dx_s);
        end
        $fclose(fd);
        $display("[TB] Dumped GF L0 output → %s (%0d pixels)", fn, gf_out_count);
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // ----- Initialization -----
        rst_n        = 0;
        write_valid  = 0;
        frame_num    = 0;
        gf_out_count = 0;

        // Clear all memory
        for(int i=0; i<32'h200000; i++) begin
            mem_spu1_f0[i] = 0; mem_spu1_f1[i] = 0;
            mem_spu2_f0[i] = 0; mem_spu2_f1[i] = 0;
        end
        for(int i=0; i<32'h400000; i++) begin
            mem_spu1_fl[i] = 0; mem_spu2_fl[i] = 0;
        end

        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);

        // =====================================================================
        // Load pyramid images into SPU1's memory region
        //
        // Frame mapping chain:
        //   TB writes: frame_num=0 (prev), frame_num=1 (curr)
        //   TAU assigns: spu1_frames = {frame_i=1, frame_i_minus_1=0}
        //   FSM decodes: curr_frame_idx=1 → FRAME1_BASE
        //                prev_frame_idx=0 → FRAME0_BASE
        //
        //   Therefore: prev_L*.hex → FRAME0_BASE, curr_L*.hex → FRAME1_BASE
        // =====================================================================
        $display("╔══════════════════════════════════════════════════════════╗");
        $display("║  LOADING PYRAMID IMAGES INTO SPU1 MEMORY               ║");
        $display("╚══════════════════════════════════════════════════════════╝");
        for(int l=0; l<=4; l++) begin
            load_layer_images(SPU1_FRAME0_BASE, SPU1_FRAME1_BASE, l);
        end

        // Quick sanity: print first few bytes of FRAME0 and FRAME1 L4
        $display("[DBG] Sanity check L4 pixel[0]: Frame0(prev)=0x%02h, Frame1(curr)=0x%02h",
                 read_byte(SPU1_FRAME0_BASE + (1280*720)+(640*360)+(320*180)+(160*90)),
                 read_byte(SPU1_FRAME1_BASE + (1280*720)+(640*360)+(320*180)+(160*90)));

        repeat(10) @(posedge clk);

        // =====================================================================
        // Simulate frame arrival notifications
        // =====================================================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════╗");
        $display("║  SIMULATING FRAME ARRIVALS                             ║");
        $display("╚══════════════════════════════════════════════════════════╝");

        // Frame 0 arrives (this is the "previous" frame, i.e. frame_i_minus_1)
        $display("[TB %0t] write_valid: frame_num=0 (prev frame ready)", $time);
        @(posedge clk);
        write_valid = 1;
        frame_num   = 2'd0;
        @(posedge clk);
        write_valid = 0;
        $display("[DBG %0t] TAU state after frame 0: %0d", $time, tau_state);

        // Wait a few cycles for TAU to register
        repeat(5) @(posedge clk);

        // Frame 1 arrives (this is the "current" frame, i.e. frame_i)
        $display("[TB %0t] write_valid: frame_num=1 (curr frame ready)", $time);
        @(posedge clk);
        write_valid = 1;
        frame_num   = 2'd1;
        @(posedge clk);
        write_valid = 0;
        $display("[DBG %0t] TAU state after frame 1: %0d (idle_spu1=%b, idle_spu2=%b)",
                 $time, tau_state, idle_spu1, idle_spu2);

        // =====================================================================
        // Wait for TAU to assign and SPU to start
        // =====================================================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════╗");
        $display("║  WAITING FOR PROCESSING                                ║");
        $display("╚══════════════════════════════════════════════════════════╝");

        // Wait for SPU1 to go non-idle
        begin
            automatic int wait_cnt = 0;
            while (idle_spu1 && wait_cnt < 200) begin
                @(posedge clk);
                wait_cnt++;
                if (wait_cnt % 10 == 0)
                    $display("[DBG %0t] Waiting for SPU1 start... TAU_state=%0d, idle_spu1=%b", 
                             $time, tau_state, idle_spu1);
            end
            if (!idle_spu1)
                $display("[TB %0t] ═══ SPU1 STARTED PROCESSING ═══", $time);
            else
                $display("[TB %0t] *** ERROR: SPU1 did not start within 200 cycles ***", $time);
        end

        // Print TAU assignment info
        $display("[DBG %0t] TAU → SPU1 frames = 4'b%04b (curr_idx=%0d, prev_idx=%0d)",
                 $time, u_dut.u_tau.spu1_frames,
                 u_dut.u_tau.spu1_frames[3:2],
                 u_dut.u_tau.spu1_frames[1:0]);

        // =====================================================================
        // Wait for L0 output through Gating Unit
        // =====================================================================
        $display("");
        $display("┌──────────────────────────────────────────────────────────┐");
        $display("│  WAITING FOR GF FLOW OUTPUT (L0: 1280×720 = 921600 px) │");
        $display("└──────────────────────────────────────────────────────────┘");

        begin
            automatic int timeout = 0;
            automatic int last_report = 0;
            automatic int expected_px = 1280 * 720;

            while (gf_out_count < expected_px && timeout < 4_000_000) begin
                @(posedge clk);
                timeout++;
                if (timeout - last_report >= 50_000) begin
                    $display("[TB %0t] GF progress: %0d/%0d px (%0dk cyc) | SPU1 layer=%0d idle=%b | GU valid=%b",
                             $time, gf_out_count, expected_px, timeout/1000,
                             spu1_layer, idle_spu1, gf_valid);
                    last_report = timeout;
                end
            end

            // Drain pipeline
            repeat(500) @(posedge clk);

            if (timeout >= 4_000_000)
                $display("[TB %0t] *** TIMEOUT: %0d / %0d pixels ***", $time, gf_out_count, expected_px);
            else
                $display("[TB %0t] ═══ All %0d pixels received in %0d cycles ═══", $time, gf_out_count, timeout);
        end

        // Wait for SPU to return idle
        begin
            automatic int wait_cnt = 0;
            while (!idle_spu1 && wait_cnt < 1000) begin
                @(posedge clk);
                wait_cnt++;
            end
        end

        // =====================================================================
        // DUMP ALL LAYER OUTPUTS
        // =====================================================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════╗");
        $display("║  DUMPING ALL LAYER OUTPUTS                             ║");
        $display("╚══════════════════════════════════════════════════════════╝");

        // L4→L1: read back from DDR flow region
        for (int l=4; l>=1; l--) begin
            dump_flow_layer_from_ddr(SPU1_FLOW_BASE, l);
        end

        // L0: from gating unit capture (also dump DDR for reference)
        dump_flow_layer_from_ddr(SPU1_FLOW_BASE, 0);
        dump_gf_output();

        // =====================================================================
        // SUMMARY
        // =====================================================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════╗");
        $display("║  GF_TOP SIMULATION COMPLETE                            ║");
        $display("╚══════════════════════════════════════════════════════════╝");
        $display("[TB] idle_spu1    = %b", idle_spu1);
        $display("[TB] idle_spu2    = %b", idle_spu2);
        $display("[TB] overflow     = %b", overflow_flag);
        $display("[TB] GF L0 pixels = %0d (gating unit)", gf_out_count);
        $display("[TB] cnt_poly_exp = %0d", cnt_poly_exp);
        $display("[TB] cnt_cbw      = %0d", cnt_cbw);
        $display("[TB] cnt_gf_valid = %0d", cnt_gf_valid);
        $display("[TB] flow_vfilt   = %0d", update_flow_vfilt);
        $display("[TB] flow_hfilt   = %0d", update_flow_hfilt);
        $display("[TB] flow_valid   = %0d", update_flow_valid);
        $display("[TB] rgi_fifo_cnt = %0d", u_dut.u_spu1.u_pipeline.u_pipeline_mwm.u_pipeline.u_gf_calc.u_rgi.fifo_count);
        $stop;
        $display("[TB]");
        $display("[TB] Output files:");
        $display("[TB]   L4: output/L4_mwm_ddr_deltas.txt (80x45   = 3600 px)");
        $display("[TB]   L3: output/L3_mwm_ddr_deltas.txt (160x90  = 14400 px)");
        $display("[TB]   L2: output/L2_mwm_ddr_deltas.txt (320x180 = 57600 px)");
        $display("[TB]   L1: output/L1_mwm_ddr_deltas.txt (640x360 = 230400 px)");
        $display("[TB]   L0: output/L0_mwm_ddr_deltas.txt (from DDR)");
        $display("[TB]   L0: output/gf_top_L0_deltas.txt  (from gating unit)");
        $display("[TB]");
        $display("[TB] Compare with golden:");
        $display("[TB]   python ../SPU/pipeline_mrm_mwm/compare_mrm_mwm.py");
        $display("╚══════════════════════════════════════════════════════════╝");

        $finish;
    end

endmodule

// =============================================================================
// AXI Read Slave Model — uses hierarchical reference to TB memory
// =============================================================================
module axi_read_slave #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 64
)(
    input  logic                      clk,
    input  logic [AXI_ADDR_WIDTH-1:0] araddr,
    input  logic [7:0]                arlen,
    input  logic                      arvalid,
    output logic                      arready,
    output logic [AXI_DATA_WIDTH-1:0] rdata,
    output logic                      rlast,
    output logic                      rvalid,
    input  logic                      rready
);
    logic [AXI_ADDR_WIDTH-1:0] latched_addr;
    logic [7:0]                latched_len;
    int                        beats_served;

    initial begin
        arready = 1'b0;
        rvalid  = 1'b0;
        rlast   = 1'b0;
    end

    always @(posedge clk) begin
        if (arvalid && !arready && !rvalid) begin
            arready <= 1'b1;
            latched_addr <= araddr;
            latched_len  <= arlen;
            beats_served <= 0;
        end else if (arready) begin
            arready <= 1'b0;
            rvalid  <= 1'b1;
            rlast   <= (beats_served == latched_len);
            for(int b=0; b<8; b++)
                rdata[b*8 +: 8] <= gf_top_tb.read_byte(latched_addr + b);
        end else if (rvalid && rready) begin
            if (rlast) begin
                rvalid <= 1'b0;
                rlast  <= 1'b0;
            end else begin
                beats_served <= beats_served + 1;
                latched_addr <= latched_addr + 8;
                rlast <= (beats_served + 1 == latched_len);
                for(int b=0; b<8; b++)
                    rdata[b*8 +: 8] <= gf_top_tb.read_byte(latched_addr + 8 + b);
            end
        end
    end
endmodule
