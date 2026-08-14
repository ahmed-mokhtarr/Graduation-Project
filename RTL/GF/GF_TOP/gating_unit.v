`timescale 1ns / 1ps
// =============================================================================
// gating_unit.v  —  Gating Unit for Dual-SPU Output Selection
//
// Serializes L0 flow output from two SPUs. Only one SPU's output is passed
// through at a time. Once an SPU starts outputting (valid goes high), it holds
// the lock until its full frame completes (921,600 pixels). The other SPU's
// output is blocked (its valid is masked). When the active SPU finishes, the
// lock releases and the next SPU can start.
//
// If no SPU is active and both become valid on the same cycle, SPU1 takes
// priority.
// =============================================================================
module gating_unit #(
    parameter FRAME_PIXELS = 921600
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── SPU 1 L0 Output ─────────────────────────────────────────────────────
    input  wire        spu1_valid,
    input  wire [15:0] spu1_flow,    // {dy[7:0], dx[7:0]}

    // ── SPU 2 L0 Output ─────────────────────────────────────────────────────
    input  wire        spu2_valid,
    input  wire [15:0] spu2_flow,    // {dy[7:0], dx[7:0]}

    // ── Gated Output ────────────────────────────────────────────────────────
    output reg         gf_valid,
    output reg  [15:0] gf_flow       // {dy[7:0], dx[7:0]}
);

    // Lock state: 0 = no lock, 1 = SPU1 active, 2 = SPU2 active
    reg [1:0] active_spu;
    reg [19:0] px_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gf_valid   <= 1'b0;
            gf_flow    <= 16'h0000;
            active_spu <= 2'd0;
            px_cnt     <= 20'd0;
        end else begin
            case (active_spu)
                2'd0: begin
                    // No SPU is active — accept first valid
                    if (spu1_valid) begin
                        gf_valid   <= 1'b1;
                        gf_flow    <= spu1_flow;
                        active_spu <= 2'd1;
                        px_cnt     <= 20'd1;
                    end else if (spu2_valid) begin
                        gf_valid   <= 1'b1;
                        gf_flow    <= spu2_flow;
                        active_spu <= 2'd2;
                        px_cnt     <= 20'd1;
                    end else begin
                        gf_valid <= 1'b0;
                    end
                end

                2'd1: begin
                    // SPU1 is active
                    if (spu1_valid) begin
                        gf_valid <= 1'b1;
                        gf_flow  <= spu1_flow;
                        if (px_cnt >= FRAME_PIXELS - 1) begin
                            active_spu <= 2'd0;
                            px_cnt     <= 20'd0;
                        end else begin
                            px_cnt <= px_cnt + 20'd1;
                        end
                    end else begin
                        gf_valid <= 1'b0;
                    end
                end

                2'd2: begin
                    // SPU2 is active
                    if (spu2_valid) begin
                        gf_valid <= 1'b1;
                        gf_flow  <= spu2_flow;
                        if (px_cnt >= FRAME_PIXELS - 1) begin
                            active_spu <= 2'd0;
                            px_cnt     <= 20'd0;
                        end else begin
                            px_cnt <= px_cnt + 20'd1;
                        end
                    end else begin
                        gf_valid <= 1'b0;
                    end
                end

                default: begin
                    active_spu <= 2'd0;
                    gf_valid   <= 1'b0;
                end
            endcase
        end
    end

endmodule
