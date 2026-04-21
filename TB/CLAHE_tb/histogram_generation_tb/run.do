vlib work
vlog *.*v
vsim -voptargs="+acc" work.histogram_generation_tb
do wave.do
run -all