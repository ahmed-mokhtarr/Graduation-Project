vlib work
vlog *.*v
vsim -voptargs="+acc" work.bilinear_interpolation_tb
do wave.do
run -all