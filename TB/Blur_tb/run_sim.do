# ==============================================================================
# QuestaSim .do file for Gaussian Blur Submodule Simulation
# ==============================================================================
# Run from the gaussian_blur_fpga/tb/ directory:
#   questasim -do run_sim.do
# Or from QuestaSim GUI:
#   do run_sim.do
# ==============================================================================

# ── Create work library ──
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# ── Compile RTL sources ──
vlog -work work ../rtl/line_buffer_bank.v
vlog -work work ../rtl/vertical_conv_7x1.v
vlog -work work ../rtl/horizontal_conv_1x7.v
vlog -work work ../rtl/gaussian_blur_top.v

# ── Compile Testbench ──
vlog -work work gaussian_blur_tb.v

# ── Load simulation ──
vsim -t 1ns -voptargs=+acc work.gaussian_blur_tb

# ── Add waveforms (key signals) ──
add wave -divider "Clock & Reset"
add wave -color yellow  /gaussian_blur_tb/clk
add wave -color red     /gaussian_blur_tb/rst_n

add wave -divider "Input AXI4-Stream"
add wave -radix hex     /gaussian_blur_tb/s_axis_tdata
add wave -color green   /gaussian_blur_tb/s_axis_tvalid
add wave -color cyan    /gaussian_blur_tb/s_axis_tready
add wave -color magenta /gaussian_blur_tb/s_axis_tlast

add wave -divider "Line Buffer Taps (Block 1 Output)"
add wave -radix hex     /gaussian_blur_tb/dut/lb_data
add wave                /gaussian_blur_tb/dut/lb_valid
add wave                /gaussian_blur_tb/dut/lb_last

add wave -divider "Vertical Conv Output (Block 2)"
add wave -radix unsigned /gaussian_blur_tb/dut/vc_data
add wave                 /gaussian_blur_tb/dut/vc_valid
add wave                 /gaussian_blur_tb/dut/vc_last

add wave -divider "Output AXI4-Stream (Blurred Pixel)"
add wave -radix unsigned /gaussian_blur_tb/m_axis_tdata
add wave -color green    /gaussian_blur_tb/m_axis_tvalid
add wave -color cyan     /gaussian_blur_tb/m_axis_tready
add wave -color magenta  /gaussian_blur_tb/m_axis_tlast

add wave -divider "Testbench Counters"
add wave -radix unsigned /gaussian_blur_tb/in_idx
add wave -radix unsigned /gaussian_blur_tb/out_idx

# ── Run simulation ──
# Run for enough time to process all 929,000 pixels
# Each pixel takes ~2 clock cycles (10ns each) + pipeline latency
# Estimate: 929000 * 2 * 10ns + margin = ~20ms
run -all

# ── Done ──
echo "================================================================"
echo " Simulation complete. Check transcript for match/mismatch report."
echo " RTL output saved to ../data/rtl_output.hex"
echo "================================================================"
