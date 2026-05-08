vlib work
vmap work work
vlog -f source.txt

vsim -voptargs=+acc work.tb_zoom_in
set SolveArrayResizeMax 500000
do wave.do
run -all
