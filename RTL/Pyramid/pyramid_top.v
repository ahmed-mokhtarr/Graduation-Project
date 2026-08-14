`timescale 1ns / 1ps

module pyramid_top (
    input  wire        clk,
    input  wire        rst_n,

    // AXI-Stream Slave (From Blur Module)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,
    input  wire        s_axis_tlast,

    // AXI4-Full Master (To DDR Memory)
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    
    output wire [31:0] m_axi_wdata, 
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    input  wire [1:0]  m_axi_bresp,

    // Config: Base Addresses
    input  wire [31:0] slot_addr_0,
    input  wire [31:0] slot_addr_1,
    input  wire [31:0] slot_addr_2,
    input  wire [31:0] slot_addr_3,

    // TAU Handshake
    output wire        write_valid,
    output wire [1:0]  frame_num
);

    // 32-bit Internal Routing Wires
    wire [31:0] L0_din, L1_din, L2_din, L3_din, L4_din;
    wire L0_wr, L1_wr, L2_wr, L3_wr, L4_wr;
    wire L0_full, L1_full, L2_full, L3_full, L4_full;
    wire eof_pulse;

    wire [31:0] L0_dout, L1_dout, L2_dout, L3_dout, L4_dout;
    wire L0_rd, L1_rd, L2_rd, L3_rd, L4_rd;
    wire L0_empty, L1_empty, L2_empty, L3_empty, L4_empty;
    wire [7:0] L0_cnt, L1_cnt, L2_cnt, L3_cnt, L4_cnt; 

    wire       cmd_valid;
    wire       cmd_ready;
    wire [2:0] cmd_layer;
    wire [9:0] cmd_len;
    wire [1:0] cmd_slot;

    pyramid_subsampler subsampler_inst (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tuser(s_axis_tuser),
        .s_axis_tlast(s_axis_tlast),
        .eof_pulse_out(eof_pulse),
        
        .L0_data(L0_din),  
        .L1_data(L1_din),  
        .L2_data(L2_din),  
        .L3_data(L3_din),  
        .L4_data(L4_din),  

        .L0_valid(L0_wr),
        .L1_valid(L1_wr),
        .L2_valid(L2_wr),
        .L3_valid(L3_wr),
        .L4_valid(L4_wr),

        .L0_full(L0_full),
        .L1_full(L1_full),
        .L2_full(L2_full),
        .L3_full(L3_full),
        .L4_full(L4_full)
    );


    pyr_sync_fifo #(.DATA_WIDTH(32), .ADDR_WIDTH(7)) fifo_L0 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(L0_wr), .din(L0_din), .full(L0_full),
        .rd_en(L0_rd), .dout(L0_dout), .empty(L0_empty), .data_count(L0_cnt)
    );

    pyr_sync_fifo #(.DATA_WIDTH(32), .ADDR_WIDTH(7)) fifo_L1 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(L1_wr), .din(L1_din), .full(L1_full),
        .rd_en(L1_rd), .dout(L1_dout), .empty(L1_empty), .data_count(L1_cnt)
    );

    pyr_sync_fifo #(.DATA_WIDTH(32), .ADDR_WIDTH(7)) fifo_L2 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(L2_wr), .din(L2_din), .full(L2_full),
        .rd_en(L2_rd), .dout(L2_dout), .empty(L2_empty), .data_count(L2_cnt)
    );

    pyr_sync_fifo #(.DATA_WIDTH(32), .ADDR_WIDTH(7)) fifo_L3 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(L3_wr), .din(L3_din), .full(L3_full),
        .rd_en(L3_rd), .dout(L3_dout), .empty(L3_empty), .data_count(L3_cnt)
    );

    pyr_sync_fifo #(.DATA_WIDTH(32), .ADDR_WIDTH(7)) fifo_L4 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(L4_wr), .din(L4_din), .full(L4_full),
        .rd_en(L4_rd), .dout(L4_dout), .empty(L4_empty), .data_count(L4_cnt)
    );

    pyramid_fsm #(.BURST_LEN(10'd64)) fsm_inst (
        .clk(clk),
        .rst_n(rst_n),
        .eof_pulse(eof_pulse),
        
        .L0_cnt({2'b00, L0_cnt}), .L1_cnt({2'b00, L1_cnt}), .L2_cnt({2'b00, L2_cnt}), 
        .L3_cnt({2'b00, L3_cnt}), .L4_cnt({2'b00, L4_cnt}),
        
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_layer(cmd_layer),
        .cmd_len(cmd_len),
        .cmd_slot(cmd_slot),
        
        .axi_bvalid(m_axi_bvalid),
        .write_valid(write_valid),
        .frame_num(frame_num)
    );

    axi4_burst_writer writer_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_layer(cmd_layer),
        .cmd_len(cmd_len),
        .cmd_slot(cmd_slot),
        
        .slot_addr_0(slot_addr_0),
        .slot_addr_1(slot_addr_1),
        .slot_addr_2(slot_addr_2),
        .slot_addr_3(slot_addr_3),
        
        .L0_rd_en(L0_rd), 
        .L1_rd_en(L1_rd), 
        .L2_rd_en(L2_rd), 
        .L3_rd_en(L3_rd), 
        .L4_rd_en(L4_rd), 
        
        .L0_dout(L0_dout),
        .L1_dout(L1_dout),
        .L2_dout(L2_dout),
        .L3_dout(L3_dout),
        .L4_dout(L4_dout),
        
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
        .m_axi_bresp(m_axi_bresp)
    );

endmodule