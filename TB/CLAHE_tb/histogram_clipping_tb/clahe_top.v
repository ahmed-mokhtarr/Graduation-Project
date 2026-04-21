module clahe_top
(
    input   wire              clk,
    input   wire              rst_n,

    input   wire              pixel_v,      // valid signal
    input   wire  [7:0]       pixel_in,     // data_in

    // BRAM PORT A (Write)
    output wire     [11:0]     wr_bram_addr,
    output wire     [15:0]     wr_bram_data,
    output wire                wr_bram_en,

    // BRAM PORT B (Read)
    output wire     [11:0]     rd_bram_addr,

    output wire                clip_ready
);
wire   [3:0]      tile_idx;
wire   [10:0]     x_count;
wire   [9:0]      y_count;
wire   [1:0]      tile_x;
wire   [1:0]      tile_y;
wire   [8:0]      tile_x_count;
wire   [7:0]      tile_y_count;
wire   [7:0]      pixel_out;
wire              pixel_v_out;

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

    // The BRAM MUX: If hist_ready is 1, give control to the Clipping module!
    assign wr_bram_addr = clipping_mode ? clip_wr_addr : hist_wr_addr;
    assign wr_bram_data = clipping_mode ? clip_wr_data : hist_wr_data;
    assign wr_bram_en   = clipping_mode ? clip_wr_en   : hist_wr_en;
    assign rd_bram_addr = clipping_mode ? clip_rd_addr : hist_rd_addr;


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

simple_dual_port_bram bram_dut
(
  .clk(clk),
  .we(wr_bram_en),
  .wr_addr(wr_bram_addr),
  .wr_data(wr_bram_data),
  .rd_addr(rd_bram_addr),
  .rd_data(rd_bram_data)
  
);

histogram_generation histogram_dut
(
  .clk(clk),
  .rst_n(rst_n),
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


endmodule