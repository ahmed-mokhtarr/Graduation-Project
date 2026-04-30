module mrm_top #(
    // Top-level Parameters that override submodules
    parameter AXI_DATA_WIDTH  = 64,
    parameter AXI_ADDR_WIDTH  = 32,
    parameter IMG_WIDTH       = 1280,
    parameter IMG_HEIGHT      = 720,
    parameter BYTES_PER_PIXEL = 1,
    parameter BYTES_PER_FLOW  = 4,
    
    // parameters for asymmetric FIFO read widths
    parameter PIXEL_WIDTH     = 8,  // matches BYTES_PER_PIXEL * 8
    parameter FLOW_WIDTH      = 32, // matches BYTES_PER_FLOW * 8
    
    // Base Addresses
    parameter FRAME0_BASE     = 32'h1000_0000,
    parameter FRAME1_BASE     = 32'h2000_0000,
    parameter FRAME2_BASE     = 32'h3000_0000,
    parameter FRAME3_BASE     = 32'h4000_0000
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---------------------------------------------------------
    // SPU FSM Control Interface
    // ---------------------------------------------------------
    input  wire [1:0]  curr_frame_idx,
    input  wire [1:0]  prev_frame_idx,
    input  wire [2:0]  current_layer, 
    input  wire        mem_read_start,
    output reg         layer_done,

    // ---------------------------------------------------------
    // Downstream Processing Interface (GF Calc & Zoom)
    // ---------------------------------------------------------
    input  wire        curr_rd_en,
    input  wire        prev_rd_en,
    input  wire        flow_rd_en,
    
    // Outputs now use the native pixel and flow widths
    output wire [PIXEL_WIDTH-1:0] curr_data_out,
    output wire [PIXEL_WIDTH-1:0] prev_data_out,
    output wire [FLOW_WIDTH-1:0]  flow_data_out,
    
    output wire        data_ready, // High when BOTH curr and prev FIFOs have data
    output wire        flow_ready, // High when flow FIFO has data

    // ---------------------------------------------------------
    // AXI4 Master Interfaces (Connected to SmartConnect)
    // ---------------------------------------------------------
    // Current Frame AXI
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

    // Previous Frame AXI
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

    // Flow Data AXI
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_flow_araddr,
    output wire [7:0]                m_axi_flow_arlen,
    output wire [2:0]                m_axi_flow_arsize,
    output wire [1:0]                m_axi_flow_arburst,
    output wire                      m_axi_flow_arvalid,
    input  wire                      m_axi_flow_arready,
    input  wire [AXI_DATA_WIDTH-1:0] m_axi_flow_rdata,
    input  wire                      m_axi_flow_rlast,
    input  wire                      m_axi_flow_rvalid,
    output wire                      m_axi_flow_rready
);

    // -------------------------------------------------------------------------
    // Internal Wires for ACU -> AXI Readers
    // -------------------------------------------------------------------------
    wire [31:0] acu_curr_addr;
    wire [31:0] acu_prev_addr;
    wire [31:0] acu_flow_addr;
    wire        acu_flow_enable;
    wire        acu_start_read;
    wire [2:0]  acu_layer_out;

    // -------------------------------------------------------------------------
    // Internal Wires for AXI Readers -> FIFOs (Write side remains AXI width)
    // -------------------------------------------------------------------------
    wire        curr_fifo_full, curr_fifo_empty;
    wire [AXI_DATA_WIDTH-1:0] curr_fifo_din;
    wire        curr_fifo_we;

    wire        prev_fifo_full, prev_fifo_empty;
    wire [AXI_DATA_WIDTH-1:0] prev_fifo_din;
    wire        prev_fifo_we;

    wire        flow_fifo_full, flow_fifo_empty;
    wire [AXI_DATA_WIDTH-1:0] flow_fifo_din;
    wire        flow_fifo_we;

    // -------------------------------------------------------------------------
    // Internal Wires for Read Completion
    // -------------------------------------------------------------------------
    wire curr_read_done;
    wire prev_read_done;
    wire flow_read_done;

    // -------------------------------------------------------------------------
    // Data & Flow Ready Logic (As per spec)
    // -------------------------------------------------------------------------
    assign data_ready = (~curr_fifo_empty) & (~prev_fifo_empty);
    assign flow_ready = (~flow_fifo_empty);

    // -------------------------------------------------------------------------
    // Address Calculation Unit (ACU)
    // -------------------------------------------------------------------------
    mem_read_acu #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .FRAME0_BASE(FRAME0_BASE),
        .FRAME1_BASE(FRAME1_BASE),
        .FRAME2_BASE(FRAME2_BASE),
        .FRAME3_BASE(FRAME3_BASE)
    ) u_acu (
        .clk              (clk),
        .rst_n            (rst_n),
        .curr_frame_idx   (curr_frame_idx),
        .prev_frame_idx   (prev_frame_idx),
        .current_layer    (current_layer),
        .mem_read_start   (mem_read_start),
        
        .curr_frame_addr  (acu_curr_addr),
        .prev_frame_addr  (acu_prev_addr),
        .flow_addr        (acu_flow_addr),
        .flow_enable      (acu_flow_enable),
        .start_read       (acu_start_read),
        .current_layer_out(acu_layer_out)
    );

    // -------------------------------------------------------------------------
    // AXI4 Master - Current Frame
    // -------------------------------------------------------------------------
    axi_read_curr #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .BYTES_PER_PIXEL(BYTES_PER_PIXEL)
    ) u_axi_read_curr (
        .clk          (clk),
        .rst_n        (rst_n),
        .curr_addr    (acu_curr_addr),
        .curr_layer   (acu_layer_out),
        .start_read   (acu_start_read),
        .read_done    (curr_read_done),
        .fifo_full    (curr_fifo_full),
        .fifo_data    (curr_fifo_din),
        .fifo_en      (curr_fifo_we),
        .araddr       (m_axi_curr_araddr),
        .arlen        (m_axi_curr_arlen),
        .arsize       (m_axi_curr_arsize),
        .arburst      (m_axi_curr_arburst),
        .arvalid      (m_axi_curr_arvalid),
        .arready      (m_axi_curr_arready),
        .rdata        (m_axi_curr_rdata),
        .rlast        (m_axi_curr_rlast),
        .rvalid       (m_axi_curr_rvalid),
        .rready       (m_axi_curr_rready)
    );

    // -------------------------------------------------------------------------
    // AXI4 Master - Previous Frame
    // -------------------------------------------------------------------------
    axi_read_prev #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .BYTES_PER_PIXEL(BYTES_PER_PIXEL)
    ) u_axi_read_prev (
        .clk          (clk),
        .rst_n        (rst_n),
        .prev_addr    (acu_prev_addr),
        .curr_layer   (acu_layer_out),
        .start_read   (acu_start_read),
        .read_done    (prev_read_done),
        .fifo_full    (prev_fifo_full),
        .fifo_data    (prev_fifo_din),
        .fifo_en      (prev_fifo_we),
        .araddr       (m_axi_prev_araddr),
        .arlen        (m_axi_prev_arlen),
        .arsize       (m_axi_prev_arsize),
        .arburst      (m_axi_prev_arburst),
        .arvalid      (m_axi_prev_arvalid),
        .arready      (m_axi_prev_arready),
        .rdata        (m_axi_prev_rdata),
        .rlast        (m_axi_prev_rlast),
        .rvalid       (m_axi_prev_rvalid),
        .rready       (m_axi_prev_rready)
    );

    // -------------------------------------------------------------------------
    // AXI4 Master - Flow Data
    // -------------------------------------------------------------------------
    axi_read_flow #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .BYTES_PER_FLOW(BYTES_PER_FLOW)
    ) u_axi_read_flow (
        .clk          (clk),
        .rst_n        (rst_n),
        .flow_addr    (acu_flow_addr),
        .current_layer(acu_layer_out),
        .flow_enable  (acu_flow_enable),
        .start_read   (acu_start_read),
        .read_done    (flow_read_done),
        .fifo_full    (flow_fifo_full),
        .fifo_data    (flow_fifo_din),
        .fifo_en      (flow_fifo_we),
        .araddr       (m_axi_flow_araddr),
        .arlen        (m_axi_flow_arlen),
        .arsize       (m_axi_flow_arsize),
        .arburst      (m_axi_flow_arburst),
        .arvalid      (m_axi_flow_arvalid),
        .arready      (m_axi_flow_arready),
        .rdata        (m_axi_flow_rdata),
        .rlast        (m_axi_flow_rlast),
        .rvalid       (m_axi_flow_rvalid),
        .rready       (m_axi_flow_rready)
    );

    // -------------------------------------------------------------------------
    // Vivado-Generated Asymmetric FIFOs
    // Write width = AXI_DATA_WIDTH
    // Read width  = PIXEL_WIDTH or FLOW_WIDTH
    // -------------------------------------------------------------------------
    
    // Current Frame FIFO
    fifo_generator_img u_curr_fifo (
        .clk    (clk),
        .srst   (~rst_n),
        .din    (curr_fifo_din),   // AXI_DATA_WIDTH
        .wr_en  (curr_fifo_we),
        .rd_en  (curr_rd_en),
        .dout   (curr_data_out),   // PIXEL_WIDTH
        .full   (curr_fifo_full),
        .empty  (curr_fifo_empty)
    );

    // Previous Frame FIFO
    fifo_generator_img u_prev_fifo (
        .clk    (clk),
        .srst   (~rst_n),
        .din    (prev_fifo_din),   // AXI_DATA_WIDTH
        .wr_en  (prev_fifo_we),
        .rd_en  (prev_rd_en),
        .dout   (prev_data_out),   // PIXEL_WIDTH
        .full   (prev_fifo_full),
        .empty  (prev_fifo_empty)
    );

    // Optical Flow FIFO 
    fifo_generator_flow u_flow_fifo (
        .clk    (clk),
        .srst   (~rst_n),
        .din    (flow_fifo_din),   // AXI_DATA_WIDTH
        .wr_en  (flow_fifo_we),
        .rd_en  (flow_rd_en),
        .dout   (flow_data_out),   // FLOW_WIDTH
        .full   (flow_fifo_full),
        .empty  (flow_fifo_empty)
    );

    // -------------------------------------------------------------------------
    // Layer Done Synchronization Logic
    // Ensures layer_done is fired only when ALL 3 AXI masters finish their tasks
    // -------------------------------------------------------------------------
    reg flag_curr_done;
    reg flag_prev_done;
    reg flag_flow_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flag_curr_done <= 1'b0;
            flag_prev_done <= 1'b0;
            flag_flow_done <= 1'b0;
            layer_done     <= 1'b0;
        end else begin
            layer_done <= 1'b0; // Default pulse

            // Clear flags when a new read starts
            if (acu_start_read) begin
                flag_curr_done <= 1'b0;
                flag_prev_done <= 1'b0;
                flag_flow_done <= 1'b0;
            end else begin
                // Latch the individual done pulses
                if (curr_read_done) flag_curr_done <= 1'b1;
                if (prev_read_done) flag_prev_done <= 1'b1;
                if (flow_read_done) flag_flow_done <= 1'b1;

                // Check if all are done (either previously flagged or pulsing right now)
                if ((flag_curr_done | curr_read_done) && 
                    (flag_prev_done | prev_read_done) && 
                    (flag_flow_done | flow_read_done)) begin
                    
                    layer_done     <= 1'b1;
                    flag_curr_done <= 1'b0;
                    flag_prev_done <= 1'b0;
                    flag_flow_done <= 1'b0;
                end
            end
        end
    end

endmodule