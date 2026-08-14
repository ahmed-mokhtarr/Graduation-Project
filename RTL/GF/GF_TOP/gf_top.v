`timescale 1ns / 1ps
// =============================================================================
// gf_top.v  —  Gunnar-Farnebäck Optical Flow Top Module
//
// Integrates:
//   1. TAU          — Task Assignment Unit (frame pair scheduling)
//   2. SPU 1        — Special Processing Unit 1 (full pyramid pipeline)
//   3. SPU 2        — Special Processing Unit 2 (full pyramid pipeline)
//   4. Gating Unit  — Muxes L0 output from whichever SPU is active
//
// External Interface:
//   - write_valid + frame_num : notification that a new frame is ready in DDR
//   - gf_valid + gf_flow     : final optical flow output (L0 delta vectors)
//   - overflow_flag           : asserted if frames arrive faster than processing
//
// Each SPU has independent AXI master ports for concurrent DDR access.
// SPU1 uses FRAME0/FRAME1 bases; SPU2 uses FRAME2/FRAME3 bases.
// Both share the same image dimensions and pipeline parameters.
// =============================================================================
module gf_top #(
    parameter PIXEL_WIDTH      = 8,
    parameter FLOW_WIDTH       = 16,
    parameter AXI_DATA_WIDTH   = 64,
    parameter AXI_ADDR_WIDTH   = 32,
    parameter IMG_WIDTH        = 1280,
    parameter IMG_HEIGHT       = 720,
    parameter FIFO_DEPTH       = 512,
    parameter FIFO_ADDR_W      = 9,
    // SPU1 DDR regions
    parameter SPU1_FRAME0_BASE = 32'h1000_0000,
    parameter SPU1_FRAME1_BASE = 32'h2000_0000,
    parameter SPU1_FLOW_BASE   = 32'h5000_0000,
    // SPU2 DDR regions
    parameter SPU2_FRAME0_BASE = 32'h3000_0000,
    parameter SPU2_FRAME1_BASE = 32'h4000_0000,
    parameter SPU2_FLOW_BASE   = 32'h6000_0000
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // ── Frame Notification (from Camera / DMA) ──────────────────────────────
    input  wire                      write_valid,   // pulse: new frame written to DDR
    input  wire [1:0]                frame_num,     // frame slot index (0–3)

    // ── GF Flow Output (from Gating Unit) ───────────────────────────────────
    output wire                      gf_valid,
    output wire [15:0]               gf_flow,       // {dy[7:0], dx[7:0]}

    // ── Status ──────────────────────────────────────────────────────────────
    output wire                      overflow_flag,
    output wire                      idle_spu1,
    output wire                      idle_spu2,

    // ── SPU1 AXI4 Read Master (Current Frame) ───────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] s1_m_axi_curr_araddr,
    output wire [7:0]                s1_m_axi_curr_arlen,
    output wire [2:0]                s1_m_axi_curr_arsize,
    output wire [1:0]                s1_m_axi_curr_arburst,
    output wire                      s1_m_axi_curr_arvalid,
    input  wire                      s1_m_axi_curr_arready,
    input  wire [AXI_DATA_WIDTH-1:0] s1_m_axi_curr_rdata,
    input  wire                      s1_m_axi_curr_rlast,
    input  wire                      s1_m_axi_curr_rvalid,
    output wire                      s1_m_axi_curr_rready,

    // ── SPU1 AXI4 Read Master (Previous Frame) ─────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] s1_m_axi_prev_araddr,
    output wire [7:0]                s1_m_axi_prev_arlen,
    output wire [2:0]                s1_m_axi_prev_arsize,
    output wire [1:0]                s1_m_axi_prev_arburst,
    output wire                      s1_m_axi_prev_arvalid,
    input  wire                      s1_m_axi_prev_arready,
    input  wire [AXI_DATA_WIDTH-1:0] s1_m_axi_prev_rdata,
    input  wire                      s1_m_axi_prev_rlast,
    input  wire                      s1_m_axi_prev_rvalid,
    output wire                      s1_m_axi_prev_rready,

    // ── SPU1 AXI4 Read Master (Flow Data) ───────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] s1_m_axi_flow_araddr,
    output wire [7:0]                s1_m_axi_flow_arlen,
    output wire [2:0]                s1_m_axi_flow_arsize,
    output wire [1:0]                s1_m_axi_flow_arburst,
    output wire                      s1_m_axi_flow_arvalid,
    input  wire                      s1_m_axi_flow_arready,
    input  wire [AXI_DATA_WIDTH-1:0] s1_m_axi_flow_rdata,
    input  wire                      s1_m_axi_flow_rlast,
    input  wire                      s1_m_axi_flow_rvalid,
    output wire                      s1_m_axi_flow_rready,

    // ── SPU1 AXI4 Write Master (Output Flow) ────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] s1_m_axi_w_awaddr,
    output wire [7:0]                s1_m_axi_w_awlen,
    output wire [2:0]                s1_m_axi_w_awsize,
    output wire [1:0]                s1_m_axi_w_awburst,
    output wire                      s1_m_axi_w_awvalid,
    input  wire                      s1_m_axi_w_awready,
    output wire [AXI_DATA_WIDTH-1:0] s1_m_axi_w_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0] s1_m_axi_w_wstrb,
    output wire                      s1_m_axi_w_wlast,
    output wire                      s1_m_axi_w_wvalid,
    input  wire                      s1_m_axi_w_wready,
    input  wire [1:0]                s1_m_axi_w_bresp,
    input  wire                      s1_m_axi_w_bvalid,
    output wire                      s1_m_axi_w_bready,

    // ── SPU2 AXI4 Read Master (Current Frame) ───────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] s2_m_axi_curr_araddr,
    output wire [7:0]                s2_m_axi_curr_arlen,
    output wire [2:0]                s2_m_axi_curr_arsize,
    output wire [1:0]                s2_m_axi_curr_arburst,
    output wire                      s2_m_axi_curr_arvalid,
    input  wire                      s2_m_axi_curr_arready,
    input  wire [AXI_DATA_WIDTH-1:0] s2_m_axi_curr_rdata,
    input  wire                      s2_m_axi_curr_rlast,
    input  wire                      s2_m_axi_curr_rvalid,
    output wire                      s2_m_axi_curr_rready,

    // ── SPU2 AXI4 Read Master (Previous Frame) ─────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] s2_m_axi_prev_araddr,
    output wire [7:0]                s2_m_axi_prev_arlen,
    output wire [2:0]                s2_m_axi_prev_arsize,
    output wire [1:0]                s2_m_axi_prev_arburst,
    output wire                      s2_m_axi_prev_arvalid,
    input  wire                      s2_m_axi_prev_arready,
    input  wire [AXI_DATA_WIDTH-1:0] s2_m_axi_prev_rdata,
    input  wire                      s2_m_axi_prev_rlast,
    input  wire                      s2_m_axi_prev_rvalid,
    output wire                      s2_m_axi_prev_rready,

    // ── SPU2 AXI4 Read Master (Flow Data) ───────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] s2_m_axi_flow_araddr,
    output wire [7:0]                s2_m_axi_flow_arlen,
    output wire [2:0]                s2_m_axi_flow_arsize,
    output wire [1:0]                s2_m_axi_flow_arburst,
    output wire                      s2_m_axi_flow_arvalid,
    input  wire                      s2_m_axi_flow_arready,
    input  wire [AXI_DATA_WIDTH-1:0] s2_m_axi_flow_rdata,
    input  wire                      s2_m_axi_flow_rlast,
    input  wire                      s2_m_axi_flow_rvalid,
    output wire                      s2_m_axi_flow_rready,

    // ── SPU2 AXI4 Write Master (Output Flow) ────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] s2_m_axi_w_awaddr,
    output wire [7:0]                s2_m_axi_w_awlen,
    output wire [2:0]                s2_m_axi_w_awsize,
    output wire [1:0]                s2_m_axi_w_awburst,
    output wire                      s2_m_axi_w_awvalid,
    input  wire                      s2_m_axi_w_awready,
    output wire [AXI_DATA_WIDTH-1:0] s2_m_axi_w_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0] s2_m_axi_w_wstrb,
    output wire                      s2_m_axi_w_wlast,
    output wire                      s2_m_axi_w_wvalid,
    input  wire                      s2_m_axi_w_wready,
    input  wire [1:0]                s2_m_axi_w_bresp,
    input  wire                      s2_m_axi_w_bvalid,
    output wire                      s2_m_axi_w_bready
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    wire [3:0] spu1_frames;
    wire [3:0] spu2_frames;
    wire       start_spu1;
    wire       start_spu2;

    wire       spu1_final_valid;
    wire [15:0] spu1_final_delta;
    wire       spu2_final_valid;
    wire [15:0] spu2_final_delta;

    // =========================================================================
    // 1. Task Assignment Unit (TAU)
    // =========================================================================
    TAU u_tau (
        .clk           (clk),
        .rst_n         (rst_n),
        .idle_spu1     (idle_spu1),
        .idle_spu2     (idle_spu2),
        .write_valid   (write_valid),
        .frame_num     (frame_num),
        .spu1_frames   (spu1_frames),
        .spu2_frames   (spu2_frames),
        .start_spu1    (start_spu1),
        .start_spu2    (start_spu2),
        .overflow_flag (overflow_flag)
    );

    // =========================================================================
    // 2. Special Processing Unit 1 (SPU1)
    // =========================================================================
    spu_top #(
        .PIXEL_WIDTH    (PIXEL_WIDTH),
        .FLOW_WIDTH     (FLOW_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .FIFO_ADDR_W    (FIFO_ADDR_W),
        .FRAME0_BASE    (SPU1_FRAME0_BASE),
        .FRAME1_BASE    (SPU1_FRAME1_BASE),
        .FRAME2_BASE    (SPU2_FRAME0_BASE),
        .FRAME3_BASE    (SPU2_FRAME1_BASE),
        .FLOW_OUT_BASE  (SPU1_FLOW_BASE)
    ) u_spu1 (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_nums       (spu1_frames),
        .start_spu        (start_spu1),
        .idle_spu         (idle_spu1),
        .final_valid_out  (spu1_final_valid),
        .final_delta_out  (spu1_final_delta),
        .current_layer    (),
        .dbg_zoom_state   (),
        .dbg_ret_state    (),
        // AXI Read Curr
        .m_axi_curr_araddr  (s1_m_axi_curr_araddr),
        .m_axi_curr_arlen   (s1_m_axi_curr_arlen),
        .m_axi_curr_arsize  (s1_m_axi_curr_arsize),
        .m_axi_curr_arburst (s1_m_axi_curr_arburst),
        .m_axi_curr_arvalid (s1_m_axi_curr_arvalid),
        .m_axi_curr_arready (s1_m_axi_curr_arready),
        .m_axi_curr_rdata   (s1_m_axi_curr_rdata),
        .m_axi_curr_rlast   (s1_m_axi_curr_rlast),
        .m_axi_curr_rvalid  (s1_m_axi_curr_rvalid),
        .m_axi_curr_rready  (s1_m_axi_curr_rready),
        // AXI Read Prev
        .m_axi_prev_araddr  (s1_m_axi_prev_araddr),
        .m_axi_prev_arlen   (s1_m_axi_prev_arlen),
        .m_axi_prev_arsize  (s1_m_axi_prev_arsize),
        .m_axi_prev_arburst (s1_m_axi_prev_arburst),
        .m_axi_prev_arvalid (s1_m_axi_prev_arvalid),
        .m_axi_prev_arready (s1_m_axi_prev_arready),
        .m_axi_prev_rdata   (s1_m_axi_prev_rdata),
        .m_axi_prev_rlast   (s1_m_axi_prev_rlast),
        .m_axi_prev_rvalid  (s1_m_axi_prev_rvalid),
        .m_axi_prev_rready  (s1_m_axi_prev_rready),
        // AXI Read Flow
        .m_axi_flow_araddr  (s1_m_axi_flow_araddr),
        .m_axi_flow_arlen   (s1_m_axi_flow_arlen),
        .m_axi_flow_arsize  (s1_m_axi_flow_arsize),
        .m_axi_flow_arburst (s1_m_axi_flow_arburst),
        .m_axi_flow_arvalid (s1_m_axi_flow_arvalid),
        .m_axi_flow_arready (s1_m_axi_flow_arready),
        .m_axi_flow_rdata   (s1_m_axi_flow_rdata),
        .m_axi_flow_rlast   (s1_m_axi_flow_rlast),
        .m_axi_flow_rvalid  (s1_m_axi_flow_rvalid),
        .m_axi_flow_rready  (s1_m_axi_flow_rready),
        // AXI Write Flow
        .m_axi_w_awaddr     (s1_m_axi_w_awaddr),
        .m_axi_w_awlen      (s1_m_axi_w_awlen),
        .m_axi_w_awsize     (s1_m_axi_w_awsize),
        .m_axi_w_awburst    (s1_m_axi_w_awburst),
        .m_axi_w_awvalid    (s1_m_axi_w_awvalid),
        .m_axi_w_awready    (s1_m_axi_w_awready),
        .m_axi_w_wdata      (s1_m_axi_w_wdata),
        .m_axi_w_wstrb      (s1_m_axi_w_wstrb),
        .m_axi_w_wlast      (s1_m_axi_w_wlast),
        .m_axi_w_wvalid     (s1_m_axi_w_wvalid),
        .m_axi_w_wready     (s1_m_axi_w_wready),
        .m_axi_w_bresp      (s1_m_axi_w_bresp),
        .m_axi_w_bvalid     (s1_m_axi_w_bvalid),
        .m_axi_w_bready     (s1_m_axi_w_bready)
    );

    // =========================================================================
    // 3. Special Processing Unit 2 (SPU2)
    // =========================================================================
    spu_top #(
        .PIXEL_WIDTH    (PIXEL_WIDTH),
        .FLOW_WIDTH     (FLOW_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .FIFO_ADDR_W    (FIFO_ADDR_W),
        .FRAME0_BASE    (SPU1_FRAME0_BASE),
        .FRAME1_BASE    (SPU1_FRAME1_BASE),
        .FRAME2_BASE    (SPU2_FRAME0_BASE),
        .FRAME3_BASE    (SPU2_FRAME1_BASE),
        .FLOW_OUT_BASE  (SPU2_FLOW_BASE)
    ) u_spu2 (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_nums       (spu2_frames),
        .start_spu        (start_spu2),
        .idle_spu         (idle_spu2),
        .final_valid_out  (spu2_final_valid),
        .final_delta_out  (spu2_final_delta),
        .current_layer    (),
        .dbg_zoom_state   (),
        .dbg_ret_state    (),
        // AXI Read Curr
        .m_axi_curr_araddr  (s2_m_axi_curr_araddr),
        .m_axi_curr_arlen   (s2_m_axi_curr_arlen),
        .m_axi_curr_arsize  (s2_m_axi_curr_arsize),
        .m_axi_curr_arburst (s2_m_axi_curr_arburst),
        .m_axi_curr_arvalid (s2_m_axi_curr_arvalid),
        .m_axi_curr_arready (s2_m_axi_curr_arready),
        .m_axi_curr_rdata   (s2_m_axi_curr_rdata),
        .m_axi_curr_rlast   (s2_m_axi_curr_rlast),
        .m_axi_curr_rvalid  (s2_m_axi_curr_rvalid),
        .m_axi_curr_rready  (s2_m_axi_curr_rready),
        // AXI Read Prev
        .m_axi_prev_araddr  (s2_m_axi_prev_araddr),
        .m_axi_prev_arlen   (s2_m_axi_prev_arlen),
        .m_axi_prev_arsize  (s2_m_axi_prev_arsize),
        .m_axi_prev_arburst (s2_m_axi_prev_arburst),
        .m_axi_prev_arvalid (s2_m_axi_prev_arvalid),
        .m_axi_prev_arready (s2_m_axi_prev_arready),
        .m_axi_prev_rdata   (s2_m_axi_prev_rdata),
        .m_axi_prev_rlast   (s2_m_axi_prev_rlast),
        .m_axi_prev_rvalid  (s2_m_axi_prev_rvalid),
        .m_axi_prev_rready  (s2_m_axi_prev_rready),
        // AXI Read Flow
        .m_axi_flow_araddr  (s2_m_axi_flow_araddr),
        .m_axi_flow_arlen   (s2_m_axi_flow_arlen),
        .m_axi_flow_arsize  (s2_m_axi_flow_arsize),
        .m_axi_flow_arburst (s2_m_axi_flow_arburst),
        .m_axi_flow_arvalid (s2_m_axi_flow_arvalid),
        .m_axi_flow_arready (s2_m_axi_flow_arready),
        .m_axi_flow_rdata   (s2_m_axi_flow_rdata),
        .m_axi_flow_rlast   (s2_m_axi_flow_rlast),
        .m_axi_flow_rvalid  (s2_m_axi_flow_rvalid),
        .m_axi_flow_rready  (s2_m_axi_flow_rready),
        // AXI Write Flow
        .m_axi_w_awaddr     (s2_m_axi_w_awaddr),
        .m_axi_w_awlen      (s2_m_axi_w_awlen),
        .m_axi_w_awsize     (s2_m_axi_w_awsize),
        .m_axi_w_awburst    (s2_m_axi_w_awburst),
        .m_axi_w_awvalid    (s2_m_axi_w_awvalid),
        .m_axi_w_awready    (s2_m_axi_w_awready),
        .m_axi_w_wdata      (s2_m_axi_w_wdata),
        .m_axi_w_wstrb      (s2_m_axi_w_wstrb),
        .m_axi_w_wlast      (s2_m_axi_w_wlast),
        .m_axi_w_wvalid     (s2_m_axi_w_wvalid),
        .m_axi_w_wready     (s2_m_axi_w_wready),
        .m_axi_w_bresp      (s2_m_axi_w_bresp),
        .m_axi_w_bvalid     (s2_m_axi_w_bvalid),
        .m_axi_w_bready     (s2_m_axi_w_bready)
    );

    // =========================================================================
    // 4. Gating Unit — Output Mux
    // =========================================================================
    gating_unit #(
        .FRAME_PIXELS(IMG_WIDTH * IMG_HEIGHT)
    ) u_gu (
        .clk        (clk),
        .rst_n      (rst_n),
        .spu1_valid (spu1_final_valid),
        .spu1_flow  (spu1_final_delta),
        .spu2_valid (spu2_final_valid),
        .spu2_flow  (spu2_final_delta),
        .gf_valid   (gf_valid),
        .gf_flow    (gf_flow)
    );

endmodule
