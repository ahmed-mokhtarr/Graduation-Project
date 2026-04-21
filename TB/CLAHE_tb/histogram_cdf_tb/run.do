vlib work
vlog *.*v
vsim -voptargs="+acc" work.histogram_cdf_tb
do wave.do
run -all