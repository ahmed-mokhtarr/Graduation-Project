`timescale 1ns / 1ps

module pipeline_mrm_mwm #(
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

    // ── SPU FSM Control ─────────────────────────────────────────────────────
    input  wire [1:0]                curr_frame_idx,
    input  wire [1:0]                prev_frame_idx,
    input  wire [2:0]                current_layer, 
    input  wire                      start,

    // ── Status Outputs ──────────────────────────────────────────────────────
    output wire                      mrm_layer_done,
    output wire                      mwm_layer_done,
    output wire                      pipeline_frame_done,
    output wire                      pipeline_zoom_done,

    // ── Final Output for Layer 0 (Bypasses DDR) ─────────────────────────────
    output wire                      final_valid_out,
    output wire [15:0]               final_delta_out,

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
    output wire                      m_axi_w_bready,

    // ── Pipeline Debug ──────────────────────────────────────────────────────
    output wire [3:0]                dbg_zoom_state,
    output wire [2:0]                dbg_ret_state
);

    // =========================================================================
    // Internal Connections
    // =========================================================================
    // From MRM to Pipeline
    wire [PIXEL_WIDTH-1:0] curr_pixel;
    wire [PIXEL_WIDTH-1:0] prev_pixel;
    wire [FLOW_WIDTH-1:0]  flow_data;
    wire                   mrm_data_ready;
    wire                   mrm_flow_ready;

    // From Pipeline to MRM
    wire                   pipeline_ready;
    wire                   pipeline_flow_rd_en;

    // Derived logic
    wire                   curr_rd_en = mrm_data_ready & pipeline_ready;
    wire                   prev_rd_en = mrm_data_ready & pipeline_ready;
    wire                   skip_zoom  = (current_layer == 3'd4);

    // =========================================================================
    // 1. MRM Top (Memory Read Module)
    // =========================================================================
    mrm_top #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .BYTES_PER_PIXEL(1),
        .BYTES_PER_FLOW (2),
        .PIXEL_WIDTH    (PIXEL_WIDTH),
        .FLOW_WIDTH     (FLOW_WIDTH),
        .FRAME0_BASE    (FRAME0_BASE),
        .FRAME1_BASE    (FRAME1_BASE),
        .FRAME2_BASE    (FRAME2_BASE),
        .FRAME3_BASE    (FRAME3_BASE),
        .FLOW_OUT_BASE  (FLOW_OUT_BASE)
    ) u_mrm (
        .clk                (clk),
        .rst_n              (rst_n),
        .curr_frame_idx     (curr_frame_idx),
        .prev_frame_idx     (prev_frame_idx),
        .current_layer      (current_layer),
        .mem_read_start     (start),
        .layer_done         (mrm_layer_done),

        .curr_rd_en         (curr_rd_en),
        .prev_rd_en         (prev_rd_en),
        .flow_rd_en         (pipeline_flow_rd_en),
        
        .curr_data_out      (curr_pixel),
        .prev_data_out      (prev_pixel),
        .flow_data_out      (flow_data),
        
        .data_ready         (mrm_data_ready),
        .flow_ready         (mrm_flow_ready),

        // AXI Curr
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

        // AXI Prev
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

        // AXI Flow
        .m_axi_flow_araddr  (m_axi_flow_araddr),
        .m_axi_flow_arlen   (m_axi_flow_arlen),
        .m_axi_flow_arsize  (m_axi_flow_arsize),
        .m_axi_flow_arburst (m_axi_flow_arburst),
        .m_axi_flow_arvalid (m_axi_flow_arvalid),
        .m_axi_flow_arready (m_axi_flow_arready),
        .m_axi_flow_rdata   (m_axi_flow_rdata),
        .m_axi_flow_rlast   (m_axi_flow_rlast),
        .m_axi_flow_rvalid  (m_axi_flow_rvalid),
        .m_axi_flow_rready  (m_axi_flow_rready)
    );

    // =========================================================================
    // 2. Pipeline + MWM Wrapper (Computes Optical Flow & Writes to DDR)
    // =========================================================================
    pipeline_mwm #(
        .PIXEL_WIDTH    (PIXEL_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .MAX_W          (IMG_WIDTH),
        .MAX_H          (IMG_HEIGHT),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .FIFO_ADDR_W    (FIFO_ADDR_W),
        .FLOW_OUT_BASE  (FLOW_OUT_BASE)
    ) u_pipeline_mwm (
        .clk              (clk),
        .rst_n            (rst_n),
        .layer_config     (current_layer),
        
        // Pipeline Inputs from MRM
        .data_ready       (mrm_data_ready),
        .curr_pixel       (curr_pixel),
        .prev_pixel       (prev_pixel),
        .flow_data        (flow_data),
        .flow_ready       (mrm_flow_ready),
        .operation_start  (start),
        .skip_zoom        (skip_zoom),
        
        // Pipeline Outputs to MRM
        .ready            (pipeline_ready),
        .flow_rd_en       (pipeline_flow_rd_en),
        .frame_done       (pipeline_frame_done),
        .zoom_done        (pipeline_zoom_done),
        
        // Pipeline Debug
        .dbg_zoom_state   (dbg_zoom_state),
        .dbg_ret_state    (dbg_ret_state),
        
        // MWM Control
        .mwm_write_start  (start),
        .mwm_layer_done   (mwm_layer_done),
        
        // Final Output for Layer 0
        .final_valid_out  (final_valid_out),
        .final_delta_out  (final_delta_out),

        // Internal observation outputs (unconnected)
        .pipeline_valid_out (),
        .pipeline_out_delta (),

        // AXI Write Master
        .m_axi_awaddr     (m_axi_w_awaddr),
        .m_axi_awlen      (m_axi_w_awlen),
        .m_axi_awsize     (m_axi_w_awsize),
        .m_axi_awburst    (m_axi_w_awburst),
        .m_axi_awvalid    (m_axi_w_awvalid),
        .m_axi_awready    (m_axi_w_awready),
        .m_axi_wdata      (m_axi_w_wdata),
        .m_axi_wstrb      (m_axi_w_wstrb),
        .m_axi_wlast      (m_axi_w_wlast),
        .m_axi_wvalid     (m_axi_w_wvalid),
        .m_axi_wready     (m_axi_w_wready),
        .m_axi_bresp      (m_axi_w_bresp),
        .m_axi_bvalid     (m_axi_w_bvalid),
        .m_axi_bready     (m_axi_w_bready)
    );

endmodule
