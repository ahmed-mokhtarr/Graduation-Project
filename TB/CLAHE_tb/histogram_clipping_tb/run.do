vlib work
vlog *.*v
vsim -voptargs="+acc" work.histogram_clipping_tb
do wave.do
run -all