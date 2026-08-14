`timescale 1ns / 1ps
// =============================================================================
// spu_top.v  —  SPU Top-Level Module
//
// Integrates:
//   1. spu_fsm           — Layer sequencing FSM (L4 → L0)
//   2. pipeline_mrm_mwm  — Full data path (MRM + GF Pipeline + MWM)
//
// The FSM auto-sequences through all pyramid layers with a single start_spu
// pulse. For each layer it asserts operation_start, then waits for the layer
// to complete before advancing to the next (smaller numbered) layer.
//
// Layer-done muxing:
//   - Layers 4→1: layer_done = mwm_layer_done  (DDR write completed)
//   - Layer 0:    layer_done = pipeline_frame_done (no DDR write, direct output)
// =============================================================================
module spu_top #(
    parameter PIXEL_WIDTH     = 8,
    parameter FLOW_WIDTH      = 16,
    parameter AXI_DATA_WIDTH  = 64,
    parameter AXI_ADDR_WIDTH  = 32,
    parameter IMG_WIDTH       = 1280,
    parameter IMG_HEIGHT      = 720,
    parameter FIFO_DEPTH      = 512,
    parameter FIFO_ADDR_W     = 9,
    parameter FRAME0_BASE     = 32'h1000_0000,
    parameter FRAME1_BASE     = 32'h2000_0000,
    parameter FRAME2_BASE     = 32'h3000_0000,
    parameter FRAME3_BASE     = 32'h4000_0000,
    parameter FLOW_OUT_BASE   = 32'h5000_0000
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // ── SPU Control ─────────────────────────────────────────────────────────
    input  wire [3:0]                frame_nums,    // {curr_frame[1:0], prev_frame[1:0]}
    input  wire                      start_spu,
    output wire                      idle_spu,

    // ── Final Output for Layer 0 (Bypasses DDR) ─────────────────────────────
    output wire                      final_valid_out,
    output wire [15:0]               final_delta_out,

    // ── Status / Debug ──────────────────────────────────────────────────────
    output wire [2:0]                current_layer,
    output wire [3:0]                dbg_zoom_state,
    output wire [2:0]                dbg_ret_state,

    // ── AXI4 Read Master (Current Frame) ────────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_curr_araddr,
    output wire [7:0]                m_axi_curr_arlen,
    output wire [2:0]                m_axi_curr_arsize,
    output wire [1:0]                m_axi_curr_arburst,
    output wire                      m_axi_curr_arvalid,
    input  wire                      m_axi_curr_arready,
    input  wire [AXI_DATA_WIDTH-1:0] m_axi_curr_rdata,
    input  wire                      m_axi_curr_rlast,
    input  wire                      m_axi_curr_rvalid,
    output wire                      m_axi_curr_rready,

    // ── AXI4 Read Master (Previous Frame) ───────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_prev_araddr,
    output wire [7:0]                m_axi_prev_arlen,
    output wire [2:0]                m_axi_prev_arsize,
    output wire [1:0]                m_axi_prev_arburst,
    output wire                      m_axi_prev_arvalid,
    input  wire                      m_axi_prev_arready,
    input  wire [AXI_DATA_WIDTH-1:0] m_axi_prev_rdata,
    input  wire                      m_axi_prev_rlast,
    input  wire                      m_axi_prev_rvalid,
    output wire                      m_axi_prev_rready,

    // ── AXI4 Read Master (Flow Data) ────────────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_flow_araddr,
    output wire [7:0]                m_axi_flow_arlen,
    output wire [2:0]                m_axi_flow_arsize,
    output wire [1:0]                m_axi_flow_arburst,
    output wire                      m_axi_flow_arvalid,
    input  wire                      m_axi_flow_arready,
    input  wire [AXI_DATA_WIDTH-1:0] m_axi_flow_rdata,
    input  wire                      m_axi_flow_rlast,
    input  wire                      m_axi_flow_rvalid,
    output wire                      m_axi_flow_rready,

    // ── AXI4 Write Master (Output Flow Data) ────────────────────────────────
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_w_awaddr,
    output wire [7:0]                m_axi_w_awlen,
    output wire [2:0]                m_axi_w_awsize,
    output wire [1:0]                m_axi_w_awburst,
    output wire                      m_axi_w_awvalid,
    input  wire                      m_axi_w_awready,
    output wire [AXI_DATA_WIDTH-1:0] m_axi_w_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_w_wstrb,
    output wire                      m_axi_w_wlast,
    output wire                      m_axi_w_wvalid,
    input  wire                      m_axi_w_wready,
    input  wire [1:0]                m_axi_w_bresp,
    input  wire                      m_axi_w_bvalid,
    output wire                      m_axi_w_bready
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    wire [1:0] curr_frame_idx;
    wire [1:0] prev_frame_idx;
    wire       operation_start;

    // pipeline_mrm_mwm status outputs
    wire       mrm_layer_done;
    wire       mwm_layer_done;
    wire       pipeline_frame_done;
    wire       pipeline_zoom_done;

    // =========================================================================
    // Layer-done muxing
    //   L4→L1: wait for BOTH MWM DDR write completion AND pipeline drain
    //   L0:    wait for pipeline frame done (no DDR write at L0)
    // =========================================================================
    reg mwm_done_latched;
    reg pipe_done_latched;
    reg [19:0] l0_px_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mwm_done_latched  <= 1'b0;
            pipe_done_latched <= 1'b0;
            l0_px_cnt         <= 20'd0;
        end else begin
            if (operation_start) begin
                mwm_done_latched  <= 1'b0;
                pipe_done_latched <= 1'b0;
                if (current_layer == 3'd0) l0_px_cnt <= 20'd0;
            end else begin
                if (mwm_layer_done)      mwm_done_latched  <= 1'b1;
                if (pipeline_frame_done) pipe_done_latched <= 1'b1;
                
                // Track Layer 0 output pixels to ensure pipeline fully drains
                if (current_layer == 3'd0 && final_valid_out) begin
                    l0_px_cnt <= l0_px_cnt + 20'd1;
                end
            end
        end
    end

    wire l0_done = (l0_px_cnt >= 20'd921600);

    wire layer_done = !operation_start && 
                      (mwm_done_latched || mwm_layer_done || current_layer == 3'd0) && 
                      (current_layer == 3'd0 ? l0_done : (pipe_done_latched || pipeline_frame_done));

    // =========================================================================
    // 1. SPU FSM — Layer Sequencing
    // =========================================================================
    spu_fsm u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .frame_nums      (frame_nums),
        .start_spu       (start_spu),
        .layer_done      (layer_done),
        .idle_spu        (idle_spu),
        .operation_start (operation_start),
        .curr_frame_idx  (curr_frame_idx),
        .prev_frame_idx  (prev_frame_idx),
        .current_layer   (current_layer)
    );

    // =========================================================================
    // 2. Pipeline + MRM + MWM (Full Data Path)
    // =========================================================================
    pipeline_mrm_mwm #(
        .PIXEL_WIDTH    (PIXEL_WIDTH),
        .FLOW_WIDTH     (FLOW_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .FIFO_ADDR_W    (FIFO_ADDR_W),
        .FRAME0_BASE    (FRAME0_BASE),
        .FRAME1_BASE    (FRAME1_BASE),
        .FRAME2_BASE    (FRAME2_BASE),
        .FRAME3_BASE    (FRAME3_BASE),
        .FLOW_OUT_BASE  (FLOW_OUT_BASE)
    ) u_pipeline (
        .clk              (clk),
        .rst_n            (rst_n),
        .curr_frame_idx   (curr_frame_idx),
        .prev_frame_idx   (prev_frame_idx),
        .current_layer    (current_layer),
        .start            (operation_start),

        .mrm_layer_done   (mrm_layer_done),
        .mwm_layer_done   (mwm_layer_done),
        .pipeline_frame_done (pipeline_frame_done),
        .pipeline_zoom_done  (pipeline_zoom_done),

        .final_valid_out  (final_valid_out),
        .final_delta_out  (final_delta_out),

        // AXI Read Curr
        .m_axi_curr_araddr  (m_axi_curr_araddr),
        .m_axi_curr_arlen   (m_axi_curr_arlen),
        .m_axi_curr_arsize  (m_axi_curr_arsize),
        .m_axi_curr_arburst (m_axi_curr_arburst),
        .m_axi_curr_arvalid (m_axi_curr_arvalid),
        .m_axi_curr_arready (m_axi_curr_arready),
        .m_axi_curr_rdata   (m_axi_curr_rdata),
        .m_axi_curr_rlast   (m_axi_curr_rlast),
        .m_axi_curr_rvalid  (m_axi_curr_rvalid),
        .m_axi_curr_rready  (m_axi_curr_rready),

        // AXI Read Prev
        .m_axi_prev_araddr  (m_axi_prev_araddr),
        .m_axi_prev_arlen   (m_axi_prev_arlen),
        .m_axi_prev_arsize  (m_axi_prev_arsize),
        .m_axi_prev_arburst (m_axi_prev_arburst),
        .m_axi_prev_arvalid (m_axi_prev_arvalid),
        .m_axi_prev_arready (m_axi_prev_arready),
        .m_axi_prev_rdata   (m_axi_prev_rdata),
        .m_axi_prev_rlast   (m_axi_prev_rlast),
        .m_axi_prev_rvalid  (m_axi_prev_rvalid),
        .m_axi_prev_rready  (m_axi_prev_rready),

        // AXI Read Flow
        .m_axi_flow_araddr  (m_axi_flow_araddr),
        .m_axi_flow_arlen   (m_axi_flow_arlen),
        .m_axi_flow_arsize  (m_axi_flow_arsize),
        .m_axi_flow_arburst (m_axi_flow_arburst),
        .m_axi_flow_arvalid (m_axi_flow_arvalid),
        .m_axi_flow_arready (m_axi_flow_arready),
        .m_axi_flow_rdata   (m_axi_flow_rdata),
        .m_axi_flow_rlast   (m_axi_flow_rlast),
        .m_axi_flow_rvalid  (m_axi_flow_rvalid),
        .m_axi_flow_rready  (m_axi_flow_rready),

        // AXI Write Flow
        .m_axi_w_awaddr     (m_axi_w_awaddr),
        .m_axi_w_awlen      (m_axi_w_awlen),
        .m_axi_w_awsize     (m_axi_w_awsize),
        .m_axi_w_awburst    (m_axi_w_awburst),
        .m_axi_w_awvalid    (m_axi_w_awvalid),
        .m_axi_w_awready    (m_axi_w_awready),
        .m_axi_w_wdata      (m_axi_w_wdata),
        .m_axi_w_wstrb      (m_axi_w_wstrb),
        .m_axi_w_wlast      (m_axi_w_wlast),
        .m_axi_w_wvalid     (m_axi_w_wvalid),
        .m_axi_w_wready     (m_axi_w_wready),
        .m_axi_w_bresp      (m_axi_w_bresp),
        .m_axi_w_bvalid     (m_axi_w_bvalid),
        .m_axi_w_bready     (m_axi_w_bready),

        // Debug
        .dbg_zoom_state     (dbg_zoom_state),
        .dbg_ret_state      (dbg_ret_state)
    );

endmodule
