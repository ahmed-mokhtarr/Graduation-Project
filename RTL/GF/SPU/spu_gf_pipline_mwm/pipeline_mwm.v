`timescale 1ns / 1ps

module pipeline_mwm #(
    parameter PIXEL_WIDTH    = 8,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 32,
    parameter MAX_W          = 1280,
    parameter MAX_H          = 720,
    parameter FIFO_DEPTH     = 512,
    parameter FIFO_ADDR_W    = 9,
    parameter FLOW_OUT_BASE  = 32'h5000_0000
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [2:0]                layer_config,
    
    // Pipeline Inputs
    input  wire                      data_ready,
    input  wire [PIXEL_WIDTH-1:0]    curr_pixel,
    input  wire [PIXEL_WIDTH-1:0]    prev_pixel,
    input  wire [15:0]               flow_data,
    input  wire                      flow_ready,
    input  wire                      operation_start,
    input  wire                      skip_zoom,
    
    // Pipeline Outputs
    output wire                      ready,
    output wire                      flow_rd_en,
    output wire                      frame_done,
    output wire                      zoom_done,
    
    // Pipeline Debug
    output wire [3:0]                dbg_zoom_state,
    output wire [2:0]                dbg_ret_state,
    
    // MWM Inputs
    input  wire                      mwm_write_start,
    
    // MWM Outputs
    output wire                      mwm_layer_done,
    
    // AXI Write channels
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                m_axi_awlen,
    output wire [2:0]                m_axi_awsize,
    output wire [1:0]                m_axi_awburst,
    output wire                      m_axi_awvalid,
    input  wire                      m_axi_awready,
    
    output wire [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire                      m_axi_wlast,
    output wire                      m_axi_wvalid,
    input  wire                      m_axi_wready,
    
    input  wire [1:0]                m_axi_bresp,
    input  wire                      m_axi_bvalid,
    output wire                      m_axi_bready,

    // Final output for the next module (active when layer 0)
    output wire                      final_valid_out,
    output wire [15:0]               final_delta_out,

    // Internal observation outputs (optional, but good for TB)
    output wire                      pipeline_valid_out,
    output wire [15:0]               pipeline_out_delta
);

    assign final_valid_out = (layer_config == 3'd0) ? pipeline_valid_out : 1'b0;
    assign final_delta_out = pipeline_out_delta;

    // ------- DUT: GF Pipeline -------
    wire pipeline_frame_start;  // retiming IDLE→ACT pulse

    gf_pipeline_top #(
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) u_pipeline (
        .clk              (clk),
        .rst_n            (rst_n),
        .layer_config     (layer_config),
        .data_ready       (data_ready),
        .curr_data_in     (curr_pixel),
        .prev_data_in     (prev_pixel),
        .flow_data        (flow_data),
        .flow_ready       (flow_ready),
        .operation_start  (operation_start),
        .skip_zoom        (skip_zoom),
        .ready            (ready),
        .flow_rd_en       (flow_rd_en),
        .valid_out        (pipeline_valid_out),
        .dbg_zoom_state   (dbg_zoom_state),
        .dbg_ret_state    (dbg_ret_state),
        .out_delta        (pipeline_out_delta),
        .frame_done       (frame_done),
        .frame_start      (pipeline_frame_start),
        .zoom_done        (zoom_done)
    );

    // ------- DUT: MWM -------
    mwm_top #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .IMG_WIDTH      (MAX_W),
        .IMG_HEIGHT     (MAX_H),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .FIFO_ADDR_W    (FIFO_ADDR_W),
        .FLOW_OUT_BASE  (FLOW_OUT_BASE)
    ) u_mwm (
        .clk             (clk),
        .rst_n           (rst_n),
        .current_layer   (layer_config),
        .write_start     (pipeline_frame_start),  // use frame_start (not mwm_write_start)
        .layer_done      (mwm_layer_done),
        .pipeline_valid  (pipeline_valid_out),
        .pipeline_delta  (pipeline_out_delta),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready)
    );

endmodule
