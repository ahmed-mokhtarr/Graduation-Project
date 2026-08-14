// =============================================================================
// Module  : init_sorter
// Purpose : 2-pass radix sort (counting sort) to sort prevList by raster
//           address (Y,X). Pass 1 sorts by X, Pass 2 stable-sorts by Y.
//
//           Each pass: CLEAR → COUNT → PREFIX → SCATTER.
//           Pass 1: src → dst (sorted by X)
//           Pass 2: dst → src (sorted by X,Y = raster order)
// =============================================================================

module init_sorter #(
    parameter IMG_WIDTH    = 1280,
    parameter IMG_HEIGHT   = 720,
    parameter MAX_FEATURES = 2048,
    parameter FEAT_W       = 64,
    parameter ADDR_W       = 11,
    parameter COL_W        = 11,
    parameter ROW_W        = 10,
    parameter COUNT_DEPTH  = 2048,
    parameter COUNT_AW     = 11,
    parameter COUNT_DW     = ADDR_W + 1
)(
    input  wire                clk,
    input  wire                rst_n,

    // ── Control ─────────────────────────────────────────────────────────────
    input  wire                start,
    input  wire [ADDR_W:0]     feat_count,
    output reg                 done,
    output reg                 busy,

    // ── Source Feature List BRAM — Port A (read in pass 1, write in pass 2) ──
    output reg  [ADDR_W-1:0]   src_addr_a,
    output reg  [FEAT_W-1:0]   src_din_a,
    output reg                 src_we_a,
    input  wire [FEAT_W-1:0]   src_dout_a,

    // ── Destination Feature List BRAM — Port A (write in pass 1), Port B (read in pass 2) ──
    output reg  [ADDR_W-1:0]   dst_addr_a,
    output reg  [FEAT_W-1:0]   dst_din_a,
    output reg                 dst_we_a,

    output reg  [ADDR_W-1:0]   dst_addr_b,
    input  wire [FEAT_W-1:0]   dst_dout_b
);

    // =========================================================================
    // Count BRAM — internal, reused for both passes
    // =========================================================================
    reg                  cnt_we;
    reg  [COUNT_AW-1:0]  cnt_wr_addr;
    reg  [COUNT_DW-1:0]  cnt_wr_data;
    reg  [COUNT_AW-1:0]  cnt_rd_addr;
    wire [COUNT_DW-1:0]  cnt_rd_data;

    simple_dual_port_bram #(
        .DATA_WIDTH (COUNT_DW),
        .ADDR_WIDTH (COUNT_AW)
    ) u_count_bram (
        .clk     (clk),
        .we      (cnt_we),
        .wr_addr (cnt_wr_addr),
        .wr_data (cnt_wr_data),
        .rd_addr (cnt_rd_addr),
        .rd_data (cnt_rd_data)
    );

    // =========================================================================
    // FSM — 4-bit encoding, 16 states
    // =========================================================================
    localparam [3:0]
        S_IDLE      = 4'd0,
        S_CLEAR     = 4'd1,
        S_CNT_RD    = 4'd2,
        S_CNT_WAIT  = 4'd3,
        S_CNT_KEY   = 4'd4,
        S_CNT_CWAIT = 4'd5,
        S_CNT_WR    = 4'd6,
        S_PFX_RD    = 4'd7,
        S_PFX_WAIT  = 4'd8,
        S_PFX_WR    = 4'd9,
        S_SCT_RD    = 4'd10,
        S_SCT_WAIT  = 4'd11,
        S_SCT_KEY   = 4'd12,
        S_SCT_CWAIT = 4'd13,
        S_SCT_WR    = 4'd14,
        S_DONE      = 4'd15;

    reg  [3:0]           state;
    reg                  pass;              // 0 = sort by X, 1 = sort by Y
    reg  [ADDR_W:0]      idx;
    reg  [COUNT_AW:0]    cidx;
    reg  [COUNT_AW:0]    num_buckets;
    reg  [FEAT_W-1:0]    entry_reg;
    reg  [COUNT_AW-1:0]  key_reg;
    reg  [COUNT_DW-1:0]  prefix_acc;

    // Forwarding for back-to-back same-key
    reg                  fwd_valid;
    reg  [COUNT_AW-1:0]  fwd_key;
    reg  [COUNT_DW-1:0]  fwd_val;

    // Helper: extract key from raw BRAM output
    wire [FEAT_W-1:0] input_data = (pass == 1'b0) ? src_dout_a : dst_dout_b;

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            pass        <= 1'b0;
            done        <= 1'b0;
            busy        <= 1'b0;
            idx         <= 0;
            cidx        <= 0;
            num_buckets <= 0;
            entry_reg   <= 0;
            key_reg     <= 0;
            prefix_acc  <= 0;
            fwd_valid   <= 1'b0;
            fwd_key     <= 0;
            fwd_val     <= 0;
            cnt_we      <= 1'b0;
            cnt_wr_addr <= 0;
            cnt_wr_data <= 0;
            cnt_rd_addr <= 0;
            src_addr_a  <= 0;
            src_din_a   <= 0;
            src_we_a    <= 1'b0;
            dst_addr_a  <= 0;
            dst_din_a   <= 0;
            dst_we_a    <= 1'b0;
            dst_addr_b  <= 0;
        end else begin
            // Defaults
            done     <= 1'b0;
            cnt_we   <= 1'b0;
            src_we_a <= 1'b0;
            dst_we_a <= 1'b0;

            case (state)

            // ─────────────────────────────────────────────────────────────
            S_IDLE: begin
                if (start && feat_count > 0) begin
                    busy        <= 1'b1;
                    pass        <= 1'b0;
                    num_buckets <= IMG_WIDTH;
                    cidx        <= 0;
                    state       <= S_CLEAR;
                end else if (start) begin
                    done <= 1'b1;
                end
            end

            // ─────────────────────────────────────────────────────────────
            // CLEAR count BRAM
            // ─────────────────────────────────────────────────────────────
            S_CLEAR: begin
                cnt_we      <= 1'b1;
                cnt_wr_addr <= cidx[COUNT_AW-1:0];
                cnt_wr_data <= 0;
                if (cidx >= num_buckets - 1) begin
                    cidx      <= 0;
                    idx       <= 0;
                    fwd_valid <= 1'b0;
                    state     <= S_CNT_RD;
                end else begin
                    cidx <= cidx + 1'b1;
                end
            end

            // ─────────────────────────────────────────────────────────────
            // COUNT: for each feature, increment count[key]
            //   4 cycles per feature: RD → WAIT → KEY → CWAIT → WR
            // ─────────────────────────────────────────────────────────────
            S_CNT_RD: begin
                if (idx >= feat_count) begin
                    cidx       <= 0;
                    prefix_acc <= 0;
                    state      <= S_PFX_RD;
                end else begin
                    if (pass == 1'b0)
                        src_addr_a <= idx[ADDR_W-1:0];
                    else
                        dst_addr_b <= idx[ADDR_W-1:0];
                    state <= S_CNT_WAIT;
                end
            end

            S_CNT_WAIT: begin
                state <= S_CNT_KEY;
            end

            S_CNT_KEY: begin
                // BRAM data available. Latch entry and extract key.
                entry_reg <= input_data;
                if (pass == 1'b0)
                    key_reg <= input_data[20:10];                              // X
                else
                    key_reg <= {{(COUNT_AW-ROW_W){1'b0}}, input_data[9:0]}; // Y

                // Issue count BRAM read at key address
                if (pass == 1'b0)
                    cnt_rd_addr <= input_data[20:10];
                else
                    cnt_rd_addr <= {{(COUNT_AW-ROW_W){1'b0}}, input_data[9:0]};

                state <= S_CNT_CWAIT;
            end

            S_CNT_CWAIT: begin
                state <= S_CNT_WR;
            end

            S_CNT_WR: begin
                // Write count[key] = old_count + 1, with forwarding
                cnt_we      <= 1'b1;
                cnt_wr_addr <= key_reg;

                if (fwd_valid && fwd_key == key_reg) begin
                    cnt_wr_data <= fwd_val + 1'b1;
                    fwd_val     <= fwd_val + 1'b1;
                end else begin
                    cnt_wr_data <= cnt_rd_data + 1'b1;
                    fwd_val     <= cnt_rd_data + 1'b1;
                end

                fwd_valid <= 1'b1;
                fwd_key   <= key_reg;
                idx       <= idx + 1'b1;
                state     <= S_CNT_RD;
            end

            // ─────────────────────────────────────────────────────────────
            // PREFIX SUM: count[i] = sum of count[0..i-1]
            //   3 cycles per bucket: RD → WAIT → WR
            // ─────────────────────────────────────────────────────────────
            S_PFX_RD: begin
                if (cidx >= num_buckets) begin
                    idx       <= 0;
                    fwd_valid <= 1'b0;
                    state     <= S_SCT_RD;
                end else begin
                    cnt_rd_addr <= cidx[COUNT_AW-1:0];
                    state       <= S_PFX_WAIT;
                end
            end

            S_PFX_WAIT: begin
                state <= S_PFX_WR;
            end

            S_PFX_WR: begin
                // count[cidx] was the raw count. Replace with prefix sum.
                cnt_we      <= 1'b1;
                cnt_wr_addr <= cidx[COUNT_AW-1:0];
                cnt_wr_data <= prefix_acc;
                prefix_acc  <= prefix_acc + cnt_rd_data;
                cidx        <= cidx + 1'b1;
                state       <= S_PFX_RD;
            end

            // ─────────────────────────────────────────────────────────────
            // SCATTER: place each feature at offset[key], increment offset
            //   5 cycles per feature: RD → WAIT → KEY → CWAIT → WR
            // ─────────────────────────────────────────────────────────────
            S_SCT_RD: begin
                if (idx >= feat_count) begin
                    // Pass complete
                    if (pass == 1'b0) begin
                        pass        <= 1'b1;
                        num_buckets <= IMG_HEIGHT;
                        cidx        <= 0;
                        state       <= S_CLEAR;
                    end else begin
                        state <= S_DONE;
                    end
                end else begin
                    if (pass == 1'b0)
                        src_addr_a <= idx[ADDR_W-1:0];
                    else
                        dst_addr_b <= idx[ADDR_W-1:0];
                    state <= S_SCT_WAIT;
                end
            end

            S_SCT_WAIT: begin
                state <= S_SCT_KEY;
            end

            S_SCT_KEY: begin
                entry_reg <= input_data;
                if (pass == 1'b0)
                    key_reg <= input_data[20:10];
                else
                    key_reg <= {{(COUNT_AW-ROW_W){1'b0}}, input_data[9:0]};

                if (pass == 1'b0)
                    cnt_rd_addr <= input_data[20:10];
                else
                    cnt_rd_addr <= {{(COUNT_AW-ROW_W){1'b0}}, input_data[9:0]};

                state <= S_SCT_CWAIT;
            end

            S_SCT_CWAIT: begin
                state <= S_SCT_WR;
            end

            S_SCT_WR: begin
                // Get offset from count BRAM (with forwarding)
                begin : scatter_blk
                    reg [COUNT_DW-1:0] offset;
                    if (fwd_valid && fwd_key == key_reg)
                        offset = fwd_val;
                    else
                        offset = cnt_rd_data;

                    // Write entry to output at sorted position
                    if (pass == 1'b0) begin
                        dst_we_a   <= 1'b1;
                        dst_addr_a <= offset[ADDR_W-1:0];
                        dst_din_a  <= entry_reg;
                    end else begin
                        src_we_a   <= 1'b1;
                        src_addr_a <= offset[ADDR_W-1:0];
                        src_din_a  <= entry_reg;
                    end

                    // Update offset: count[key]++
                    cnt_we      <= 1'b1;
                    cnt_wr_addr <= key_reg;
                    cnt_wr_data <= offset + 1'b1;

                    // Forwarding
                    fwd_valid <= 1'b1;
                    fwd_key   <= key_reg;
                    fwd_val   <= offset + 1'b1;
                end

                idx   <= idx + 1'b1;
                state <= S_SCT_RD;

                if (pass == 1'b1 && idx < 5) begin
                    $display("[SORTER P1] idx=%0d key=%0d offset=%0d entry=%h", idx, key_reg, scatter_blk.offset, entry_reg);
                end
            end

            // ─────────────────────────────────────────────────────────────
            S_DONE: begin
                done <= 1'b1;
                busy <= 1'b0;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;

            endcase
        end
    end

endmodule
