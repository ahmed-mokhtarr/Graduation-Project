`timescale 1ns / 1ps

module axi4_burst_writer (
    input  wire        clk,
    input  wire        rst_n,

    // Command Interface
    input  wire        cmd_valid,
    output reg         cmd_ready,
    input  wire [2:0]  cmd_layer,
    input  wire [9:0]  cmd_len,     
    input  wire [1:0]  cmd_slot,

    // Slot Base Addresses
    input  wire [31:0] slot_addr_0,
    input  wire [31:0] slot_addr_1,
    input  wire [31:0] slot_addr_2,
    input  wire [31:0] slot_addr_3,

    // FIFO Read Interfaces
    output wire        L0_rd_en, 
    output wire        L1_rd_en, 
    output wire        L2_rd_en, 
    output wire        L3_rd_en, 
    output wire        L4_rd_en,

    // FIFOs output 32 bits 
    input wire [31:0]  L0_dout,
    input wire [31:0]  L1_dout,
    input wire [31:0]  L2_dout,
    input wire [31:0]  L3_dout,
    input wire [31:0]  L4_dout, 

    // AXI4 Write Address Channel (AW)
    output reg  [31:0] m_axi_awaddr,
    output reg  [7:0]  m_axi_awlen, 
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,

    // AXI4 Write Data Channel (W) 
    output wire [31:0] m_axi_wdata,
    output reg         m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,

    // AXI4 Write Response Channel (B)
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    input  wire [1:0]  m_axi_bresp
);

    // 3'b010 = 4 Bytes per beat (32-bit bus)
    assign m_axi_awsize  = 3'b010; 
    assign m_axi_awburst = 2'b01;

    // Offsets are strictly physical memory byte offsets. They remain identical.
    localparam L0_OFFSET = 32'd0;
    localparam L1_OFFSET = L0_OFFSET + (1280 * 720);         
    localparam L2_OFFSET = L1_OFFSET + (640 * 360);
    localparam L3_OFFSET = L2_OFFSET + (320 * 180);
    localparam L4_OFFSET = L3_OFFSET + (160 * 90);

    localparam [1:0] IDLE  = 2'b00,
                     AW    = 2'b01,
                     W     = 2'b10,
                     B     = 2'b11;

    reg [1:0] state, next_state;
    reg [31:0] current_base_addr;
    reg [9:0]  beats_remaining; 
    reg [2:0]  active_layer;

    assign m_axi_wdata = (active_layer == 3'd0) ? L0_dout :
                         (active_layer == 3'd1) ? L1_dout :
                         (active_layer == 3'd2) ? L2_dout :
                         (active_layer == 3'd3) ? L3_dout :
                         (active_layer == 3'd4) ? L4_dout : 32'h0;

    // Combinational Read Enables to prevent shift
    assign L0_rd_en = (state == W && m_axi_wvalid && m_axi_wready && active_layer == 3'd0);
    assign L1_rd_en = (state == W && m_axi_wvalid && m_axi_wready && active_layer == 3'd1);
    assign L2_rd_en = (state == W && m_axi_wvalid && m_axi_wready && active_layer == 3'd2);
    assign L3_rd_en = (state == W && m_axi_wvalid && m_axi_wready && active_layer == 3'd3);
    assign L4_rd_en = (state == W && m_axi_wvalid && m_axi_wready && active_layer == 3'd4);                 

    always @(*) begin
        case (cmd_slot)
            2'b00: current_base_addr = slot_addr_0;
            2'b01: current_base_addr = slot_addr_1;
            2'b10: current_base_addr = slot_addr_2;
            2'b11: current_base_addr = slot_addr_3;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (cmd_valid) next_state = AW;
            AW:   if (m_axi_awready && m_axi_awvalid) next_state = W;
            W:    if (m_axi_wready && m_axi_wvalid && m_axi_wlast) next_state = B;
            B:    if (m_axi_bvalid) next_state = IDLE; 
        endcase
    end

    reg [31:0] L0_ptr, L1_ptr, L2_ptr, L3_ptr, L4_ptr;
    reg [1:0]  prev_slot;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_ready       <= 1'b1;
            m_axi_awvalid   <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            m_axi_wlast     <= 1'b0;
            m_axi_bready    <= 1'b0;
            beats_remaining <= 10'd0;
            
            prev_slot <= 2'b00;
            L0_ptr <= 32'd0; L1_ptr <= 32'd0; L2_ptr <= 32'd0; 
            L3_ptr <= 32'd0; L4_ptr <= 32'd0;
        end else begin
            
            prev_slot <= cmd_slot;
            if (cmd_slot != prev_slot) begin
                L0_ptr <= 32'd0; L1_ptr <= 32'd0; L2_ptr <= 32'd0; 
                L3_ptr <= 32'd0; L4_ptr <= 32'd0;
            end

            case (state)
                IDLE: begin
                    cmd_ready <= 1'b1;
                    m_axi_bready <= 1'b0;
                    if (cmd_valid) begin
                        cmd_ready       <= 1'b0;
                        active_layer    <= cmd_layer;
                        beats_remaining <= cmd_len;
                        m_axi_awlen     <= (cmd_len <= 10'd256) ? (cmd_len[7:0] - 8'd1) : 8'hFF;
                        m_axi_awvalid   <= 1'b1;

                        // Memory pointers must increment by (burst length * 4 bytes)
                        case (cmd_layer)
                            3'd0: begin m_axi_awaddr <= current_base_addr + L0_OFFSET + L0_ptr; L0_ptr <= L0_ptr + (cmd_len << 2); end
                            3'd1: begin m_axi_awaddr <= current_base_addr + L1_OFFSET + L1_ptr; L1_ptr <= L1_ptr + (cmd_len << 2); end
                            3'd2: begin m_axi_awaddr <= current_base_addr + L2_OFFSET + L2_ptr; L2_ptr <= L2_ptr + (cmd_len << 2); end
                            3'd3: begin m_axi_awaddr <= current_base_addr + L3_OFFSET + L3_ptr; L3_ptr <= L3_ptr + (cmd_len << 2); end
                            3'd4: begin m_axi_awaddr <= current_base_addr + L4_OFFSET + L4_ptr; L4_ptr <= L4_ptr + (cmd_len << 2); end
                            default: m_axi_awaddr <= current_base_addr;
                        endcase
                    end
                end

                AW: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        m_axi_wlast   <= (beats_remaining == 10'd1);
                    end
                end

                W: begin
                    if (m_axi_wready && m_axi_wvalid) begin
                        beats_remaining <= beats_remaining - 1'b1;
                        if (beats_remaining > 10'd1) begin
                            m_axi_wlast <= (beats_remaining == 10'd2);
                        end else begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                        end
                    end
                end

                B: begin
                    m_axi_wvalid <= 1'b0;
                end
            endcase
        end
    end
endmodule