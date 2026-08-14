module clahe_top #(
    parameter DDR_BASE_A = 32'h1000_0000,
    parameter DDR_BASE_B = 32'h1010_0000
)
(
    input   wire              clk,
    input   wire              rst_n,

    // Camera / pixel source
    input   wire              frame_start,     // start-of-frame pulse
    input   wire              pixel_v,         // pixel valid
    input   wire  [7:0]       pixel_in,        // pixel data

    // Enhanced pixel output
    output  wire  [7:0]       final_pixel_out,
    output  wire              final_pixel_v_out,

    // Status
    output  wire              cdf_ready,
    output  wire              read_start_out,

    // ====== AXI4 Master Interface (Write + Read share one port) ======
    // Write Address Channel
    output wire [31:0]  m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    // Write Data Channel
    output wire [31:0]  m_axi_wdata,
    output wire [3:0]   m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,
    // Write Response Channel
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,
    // Read Address Channel
    output wire [31:0]  m_axi_araddr,
    output wire [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    // Read Data Channel
    input  wire [31:0]  m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready
);

// =====================================================================
//  Internal Wires – Tile Generation
// =====================================================================
wire   [3:0]      tile_idx;
wire   [10:0]     x_count;
wire   [9:0]      y_count;
wire   [1:0]      tile_x;
wire   [1:0]      tile_y;
wire   [8:0]      tile_x_count;
wire   [7:0]      tile_y_count;
wire   [7:0]      pixel_out;
wire              pixel_v_out;

// =====================================================================
//  Internal Wires – Histogram BRAM (16-bit x 4096)
// =====================================================================
wire    [15:0]     rd_bram_data;

wire hist_ready;
wire clipping_mode;

    // Wires for the Histogram Module
    wire [11:0] hist_wr_addr, hist_rd_addr;
    wire [15:0] hist_wr_data;
    wire        hist_wr_en;

    // Wires for the Clipping Module
    wire [11:0] clip_wr_addr, clip_rd_addr;
    wire [15:0] clip_wr_data;
    wire        clip_wr_en;

    wire clip_ready;

    // Wires for the CDF Module
    wire [3:0]  cdf_tile_idx;
    wire [11:0] cdf_rd_addr;
    wire [7:0]  cdf_wr_addr;
    wire [7:0]  cdf_wr_data;
    wire        cdf_wr_en;
    wire        cdf_mode;

    // Wires for the BRAM Clear Controller
    wire [11:0] clear_wr_addr;
    wire [15:0] clear_wr_data;
    wire        clear_wr_en;
    wire        clear_done;
    wire        clear_mode;

    // Wires for the Frame Sync FSM
    wire        clear_start;
    wire        read_start;
    assign      read_start_out = read_start;
    wire [31:0] write_base_addr;
    wire [31:0] read_base_addr;

    // Wires for AXI Write Master
    wire        write_done;

    // Wires for AXI Read Master  (DDR -> bilinear path)
    wire [7:0]  ddr_pixel_out;
    wire        ddr_pixel_v_out;
    wire        read_frame_done;

// =====================================================================
//  Histogram BRAM Write MUX  (3-to-1, priority: clear > clip > histo)
// =====================================================================
    wire [11:0] wr_bram_addr;
    wire [15:0] wr_bram_data;
    wire        wr_bram_en;
    wire [11:0] rd_bram_addr;

    assign wr_bram_addr = clear_mode    ? clear_wr_addr :
                          clipping_mode ? clip_wr_addr  : hist_wr_addr;
    assign wr_bram_data = clear_mode    ? clear_wr_data :
                          clipping_mode ? clip_wr_data  : hist_wr_data;
    assign wr_bram_en   = clear_mode    ? clear_wr_en   :
                          clipping_mode ? clip_wr_en    : hist_wr_en;

    // Read MUX (same as before – clear never reads)
    assign rd_bram_addr = cdf_mode ? cdf_rd_addr : (clipping_mode ? clip_rd_addr : hist_rd_addr);

// =====================================================================
//  Tile Generation
// =====================================================================
tile_generation tile_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .pixel_v(pixel_v),
  .pixel_in(pixel_in),
  .x_count(x_count),
  .y_count(y_count),
  .tile_x(tile_x),
  .tile_y(tile_y),
  .tile_idx(tile_idx),
  .tile_x_count(tile_x_count),
  .tile_y_count(tile_y_count),
  .pixel_out(pixel_out),
  .pixel_v_out(pixel_v_out)
);

// =====================================================================
//  Histogram BRAM  (simple dual port, 16-bit x 4096)
// =====================================================================
simple_dual_port_bram bram_dut
(
  .clk(clk),
  .we(wr_bram_en),
  .wr_addr(wr_bram_addr),
  .wr_data(wr_bram_data),
  .rd_addr(rd_bram_addr),
  .rd_data(rd_bram_data)
);

// =====================================================================
//  Histogram Generation  (+ frame_start for multi-frame)
// =====================================================================
histogram_generation histogram_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .frame_start(frame_start),
  .pixel_v(pixel_v_out),
  .pixel_in(pixel_out),
  .tile_idx(tile_idx),
  .wr_bram_addr(hist_wr_addr),
  .wr_bram_data(hist_wr_data),
  .wr_bram_en(hist_wr_en),
  .rd_bram_addr(hist_rd_addr),
  .rd_bram_data(rd_bram_data),
  .hist_ready(hist_ready)
);

// =====================================================================
//  Clipping & Redistribution
// =====================================================================
clipping_redistribution clipping_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .hist_ready(hist_ready),
  .wr_bram_addr(clip_wr_addr),
  .wr_bram_data(clip_wr_data),
  .wr_bram_en(clip_wr_en),
  .rd_bram_addr(clip_rd_addr),
  .rd_bram_data(rd_bram_data),
  .clip_ready(clip_ready),
  .clipping_mode(clipping_mode)
);

// =====================================================================
//  Histogram Equalization (CDF)
// =====================================================================
histogram_equalization cdf_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .clip_ready(clip_ready),
  .wr_bram_addr(cdf_wr_addr),
  .wr_bram_data(cdf_wr_data),
  .wr_bram_en(cdf_wr_en),
  .rd_bram_addr(cdf_rd_addr),
  .rd_bram_data(rd_bram_data),
  .tile_idx(cdf_tile_idx),
  .cdf_ready(cdf_ready),
  .cdf_mode(cdf_mode)
);

// =====================================================================
//  16 CDF BRAMs  (8-bit x 256 each)
// =====================================================================
    wire [15:0] cdf_wr_en_array;
    wire [7:0]  cdf_output_data [0:15];
    wire [7:0]  interp_rd_addr;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : CDF_BRAM_ARRAY
            assign cdf_wr_en_array[i] = (cdf_tile_idx == i) ? cdf_wr_en : 1'b0;

            simple_dual_port_bram #(
                .DATA_WIDTH(8),
                .ADDR_WIDTH(8)
            ) cdf_bram_dut
            (
                .clk(clk),
                .we(cdf_wr_en_array[i]),
                .wr_addr(cdf_wr_addr),
                .wr_data(cdf_wr_data),
                .rd_addr(interp_rd_addr),
                .rd_data(cdf_output_data[i])
            );
        end
    endgenerate

// =====================================================================
//  BRAM Clear Controller
// =====================================================================
bram_clear_controller clear_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .clear_start(clear_start),
  .wr_addr(clear_wr_addr),
  .wr_data(clear_wr_data),
  .wr_en(clear_wr_en),
  .clear_done(clear_done),
  .clear_mode(clear_mode)
);

// =====================================================================
//  Frame Synchronisation FSM
// =====================================================================
frame_sync_fsm #(
  .DDR_BASE_A(DDR_BASE_A),
  .DDR_BASE_B(DDR_BASE_B)
) fsm_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .frame_start(frame_start),
  .cdf_ready(cdf_ready),
  .clear_done(clear_done),
  .clear_start(clear_start),
  .read_frame_done(read_frame_done),
  .read_start(read_start),
  .write_base_addr(write_base_addr),
  .read_base_addr(read_base_addr)
);

// =====================================================================
//  AXI Write Master  (camera pixels -> DDR)
// =====================================================================
axi_write_master wr_master_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .pixel_v(pixel_v),
  .pixel_in(pixel_in),
  .frame_start(frame_start),
  .frame_base_addr(write_base_addr),
  .write_done(write_done),
  // AXI Write channels
  .m_axi_awaddr(m_axi_awaddr),
  .m_axi_awlen(m_axi_awlen),
  .m_axi_awsize(m_axi_awsize),
  .m_axi_awburst(m_axi_awburst),
  .m_axi_awvalid(m_axi_awvalid),
  .m_axi_awready(m_axi_awready),
  .m_axi_wdata(m_axi_wdata),
  .m_axi_wstrb(m_axi_wstrb),
  .m_axi_wlast(m_axi_wlast),
  .m_axi_wvalid(m_axi_wvalid),
  .m_axi_wready(m_axi_wready),
  .m_axi_bresp(m_axi_bresp),
  .m_axi_bvalid(m_axi_bvalid),
  .m_axi_bready(m_axi_bready)
);

// =====================================================================
//  AXI Read Master  (DDR -> bilinear interpolation)
// =====================================================================
axi_read_master rd_master_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .read_start(read_start),
  .frame_base_addr(read_base_addr),
  .read_done(read_frame_done),
  .pixel_out(ddr_pixel_out),
  .pixel_v_out(ddr_pixel_v_out),
  // AXI Read channels
  .m_axi_araddr(m_axi_araddr),
  .m_axi_arlen(m_axi_arlen),
  .m_axi_arsize(m_axi_arsize),
  .m_axi_arburst(m_axi_arburst),
  .m_axi_arvalid(m_axi_arvalid),
  .m_axi_arready(m_axi_arready),
  .m_axi_rdata(m_axi_rdata),
  .m_axi_rresp(m_axi_rresp),
  .m_axi_rlast(m_axi_rlast),
  .m_axi_rvalid(m_axi_rvalid),
  .m_axi_rready(m_axi_rready)
);

// =====================================================================
//  Pixel Counter  (DDR read -> x/y coordinates for bilinear)
// =====================================================================
    wire [7:0]  cnt_pixel_out;
    wire        cnt_pixel_v_out;
    wire [10:0] cnt_x_count;
    wire [9:0]  cnt_y_count;

pixel_counter counter_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .pixel_v(ddr_pixel_v_out),
  .pixel_in(ddr_pixel_out),
  .x_count(cnt_x_count),
  .y_count(cnt_y_count),
  .pixel_out(cnt_pixel_out),
  .pixel_v_out(cnt_pixel_v_out)
);

// =====================================================================
//  4 x 16-to-1 CDF BRAM Data MUXes
// =====================================================================
    wire [3:0] TL_id, TR_id, BL_id, BR_id;

    reg [7:0] TL_data_routed;
    reg [7:0] TR_data_routed;
    reg [7:0] BL_data_routed;
    reg [7:0] BR_data_routed;

    always @(*) begin
        TL_data_routed = cdf_output_data[TL_id];
        TR_data_routed = cdf_output_data[TR_id];
        BL_data_routed = cdf_output_data[BL_id];
        BR_data_routed = cdf_output_data[BR_id];
    end

// =====================================================================
//  Bilinear Interpolation
// =====================================================================
bilinear_interpolation interpolation_dut
(
  .clk(clk),
  .rst_n(rst_n),
  .pixel_in(cnt_pixel_out),
  .pixel_v(cnt_pixel_v_out),
  .x_count(cnt_x_count),
  .y_count(cnt_y_count),
  .rd_bram_addr(interp_rd_addr),
  .tl_idx(TL_id),
  .tr_idx(TR_id),
  .bl_idx(BL_id),
  .br_idx(BR_id),
  .tl_data(TL_data_routed),
  .tr_data(TR_data_routed),
  .bl_data(BL_data_routed),
  .br_data(BR_data_routed),
  .pixel_out(final_pixel_out),
  .pixel_v_out(final_pixel_v_out)
);

endmodule