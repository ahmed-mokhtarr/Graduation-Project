# =============================================================================
# run_gf_top.do  —  ModelSim compile & run script for GF_TOP
#
# Usage (from GF_TOP/ directory):
#   vsim -c -do "do run_gf_top.do"
# =============================================================================

if {[file exists work] == 0} {
    vlib work
}
vmap work work

# ── Shared primitives ────────────────────────────────────────────────────────
vlog -quiet -work work ../Update_Flow/simple_dual_port_bram.v
vlog -quiet -work work ../coef_bram_window/simple_dual_port_uram.v
vlog -quiet -work work ../Update_Flow/gf_line_buffer.v
vlog -quiet -work work ../Update_Flow/window_shift_reg.v

# ── Poly_Exp filters + top ───────────────────────────────────────────────────
vlog -quiet -work work ../Poly_Exp/p0_filter.v
vlog -quiet -work work ../Poly_Exp/p1_filter.v
vlog -quiet -work work ../Poly_Exp/p2_filter.v
vlog -quiet -work work ../Poly_Exp/polyexp_top.v

# ── Retiming + coef_gen_top ──────────────────────────────────────────────────
vlog -quiet -work work ../Retiming/retiming.v
vlog -quiet -work work ../Retiming/coef_gen_top.v

# ── coef_bram_window + prev_coef_fifo + mapped_coef_gen_top ──────────────────
vlog -quiet -work work ../coef_bram_window/coef_bram_window.v
vlog -quiet -work work ../coef_bram_window/prev_coef_fifo.v
vlog -quiet -work work ../coef_bram_window/mapped_coef_gen_top.v
vlog -quiet -work work ../coef_bram_window/row_gap_inserter.v

# ── Update pipeline ─────────────────────────────────────────────────────────
vlog -quiet -work work ../Update_Flow/filter_15tap.v
vlog -quiet -work work ../Update_Matrices/update_matrices.v
vlog -quiet -work work ../Update_Flow/update_flow.v
vlog -quiet -work work ../Update_Top/update_top.v

# ── GF Calc Top ─────────────────────────────────────────────────────────────
vlog -quiet -work work ../gf_calc_top/gf_calc_top.v

# ── GF Pipeline modules ────────────────────────────────────────────────────
vlog -quiet -work work ../gf_pipeline_top/gf_sync_fifo.v
vlog -quiet -work work ../Zoom_In/zoom_in.v
vlog -quiet -work work ../gf_pipeline_top/gf_pipeline_top.v

# ── MWM modules ────────────────────────────────────────────────────────────
vlog -quiet -work work ../SPU/spu_gf_pipline_mwm/mwm_acu.v
vlog -quiet -work work ../SPU/spu_gf_pipline_mwm/axi_write_flow.v
vlog -quiet -work work ../SPU/spu_gf_pipline_mwm/mwm_top.v
vlog -quiet -work work ../SPU/spu_gf_pipline_mwm/pipeline_mwm.v

# ── MRM modules ────────────────────────────────────────────────────────────
vlog -quiet -work work ../SPU/MRM/MRM_ACU.v
vlog -quiet -work work ../SPU/MRM/axi_read_curr.v
vlog -quiet -work work ../SPU/MRM/axi_read_prev.v
vlog -quiet -work work ../SPU/MRM/axi_read_flow.v
vlog -quiet -work work -sv ../SPU/MRM/fifo_asym.v
vlog -quiet -work work ../SPU/MRM/mrm_top.v

# ── Pipeline MRM+MWM wrapper ───────────────────────────────────────────────
vlog -quiet -work work ../SPU/pipeline_mrm_mwm/pipeline_mrm_mwm.v

# ── SPU modules ─────────────────────────────────────────────────────────────
vlog -quiet -work work ../SPU/spu_fsm.v
vlog -quiet -work work ../SPU/spu_top.v

# ── TAU ─────────────────────────────────────────────────────────────────────
vlog -quiet -work work ../TAU.v

# ── GF_TOP modules ──────────────────────────────────────────────────────────
vlog -quiet -work work gating_unit.v
vlog -quiet -work work gf_top.v

# ── Testbench ────────────────────────────────────────────────────────────────
vlog -quiet -work work -sv gf_top_tb.sv

# ── Create output directory ─────────────────────────────────────────────────
file mkdir output

# ── Elaborate & run ─────────────────────────────────────────────────────────
vsim -c -voptargs="+acc" -t 1ns work.gf_top_tb

# Log top-level signals
log /*
run -all
