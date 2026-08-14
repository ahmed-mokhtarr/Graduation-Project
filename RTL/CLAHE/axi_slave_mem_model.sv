`timescale 1ns / 1ps
// ============================================================================
//  Behavioral AXI4 Slave Memory Model
//  - Responds to AXI4 bursts (INCR only, 32-bit data bus)
//  - Sized for 2 x 720p frames  (2 MB region starting at MEM_BASE)
//  - Purely for simulation – NOT synthesisable
// ============================================================================
module axi_slave_mem_model #(
    parameter MEM_BASE  = 32'h1000_0000,
    parameter MEM_BYTES = 2 * 1024 * 1024    // 2 MB
)(
    input  wire        clk,
    input  wire        rst_n,

    // Write Address
    input  wire [31:0] s_axi_awaddr,
    input  wire [7:0]  s_axi_awlen,
    input  wire [2:0]  s_axi_awsize,
    input  wire [1:0]  s_axi_awburst,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,

    // Write Data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wlast,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,

    // Write Response
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    // Read Address
    input  wire [31:0] s_axi_araddr,
    input  wire [7:0]  s_axi_arlen,
    input  wire [2:0]  s_axi_arsize,
    input  wire [1:0]  s_axi_arburst,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,

    // Read Data
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rlast,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    // Memory array  (byte-addressable, stored as 32-bit words)
    localparam MEM_WORDS = MEM_BYTES / 4;
    reg [31:0] mem [0:MEM_WORDS-1];

    // Initialise to zero
    integer k;
    initial for (k = 0; k < MEM_WORDS; k = k + 1) mem[k] = 32'd0;

    // Internal state
    reg [31:0] wr_addr;
    reg [7:0]  wr_beats_left;
    reg        wr_active;

    reg [31:0] rd_addr;
    reg [7:0]  rd_beats_left;
    reg        rd_active;

    // Address to word index
    function [31:0] addr2idx;
        input [31:0] addr;
        addr2idx = (addr - MEM_BASE) >> 2;
    endfunction

    // ---------------------------------------------------------------
    //  Write Channel
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            wr_active      <= 1'b0;
            wr_addr        <= 32'd0;
            wr_beats_left  <= 8'd0;
        end else begin
            // Default: deassert bvalid once accepted
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (!wr_active) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b0;
                // Accept write address
                if (s_axi_awvalid && s_axi_awready) begin
                    wr_addr       <= s_axi_awaddr;
                    wr_beats_left <= s_axi_awlen;  // N beats remaining after first
                    wr_active     <= 1'b1;
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b1;
                end
            end else begin
                // Accept write data
                if (s_axi_wvalid && s_axi_wready) begin
                    mem[addr2idx(wr_addr)] <= s_axi_wdata;
                    wr_addr <= wr_addr + 32'd4;

                    if (wr_beats_left == 0) begin
                        // Last beat
                        wr_active     <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        s_axi_bvalid  <= 1'b1;
                        s_axi_bresp   <= 2'b00; // OKAY
                    end else begin
                        wr_beats_left <= wr_beats_left - 8'd1;
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------
    //  Read Channel
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
            s_axi_rlast   <= 1'b0;
            rd_active      <= 1'b0;
            rd_addr        <= 32'd0;
            rd_beats_left  <= 8'd0;
        end else begin
            if (!rd_active) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b0;
                s_axi_rlast   <= 1'b0;
                // Accept read address
                if (s_axi_arvalid && s_axi_arready) begin
                    rd_addr       <= s_axi_araddr;
                    rd_beats_left <= s_axi_arlen;
                    rd_active     <= 1'b1;
                    s_axi_arready <= 1'b0;
                    // Present first beat immediately
                    s_axi_rdata   <= mem[addr2idx(s_axi_araddr)];
                    s_axi_rvalid  <= 1'b1;
                    s_axi_rresp   <= 2'b00;
                    s_axi_rlast   <= (s_axi_arlen == 0);
                end
            end else begin
                // Serve read data
                if (s_axi_rvalid && s_axi_rready) begin
                    if (rd_beats_left == 0) begin
                        // Last beat accepted
                        rd_active    <= 1'b0;
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                    end else begin
                        rd_addr       <= rd_addr + 32'd4;
                        rd_beats_left <= rd_beats_left - 8'd1;
                        s_axi_rdata   <= mem[addr2idx(rd_addr + 32'd4)];
                        s_axi_rlast   <= (rd_beats_left == 1);
                    end
                end
            end
        end
    end

endmodule
