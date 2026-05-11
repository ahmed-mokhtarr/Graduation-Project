vlib work
vlog *.*v
vsim -voptargs="+acc" work.tb_update_matrices
do wave.do
run -all