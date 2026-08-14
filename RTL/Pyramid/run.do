vlib work
vlog *.*v
vsim -voptargs="+acc" work.pyramid_top_tb
do wave.do
run -all