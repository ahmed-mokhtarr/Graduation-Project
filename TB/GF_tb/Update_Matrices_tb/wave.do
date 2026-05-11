onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_update_matrices/uut/clk
add wave -noupdate /tb_update_matrices/uut/rst_n
add wave -noupdate /tb_update_matrices/uut/valid_in
add wave -noupdate /tb_update_matrices/uut/layer_id_in
add wave -noupdate /tb_update_matrices/uut/prev_frame_r2
add wave -noupdate /tb_update_matrices/uut/prev_frame_r3
add wave -noupdate /tb_update_matrices/uut/prev_frame_r4
add wave -noupdate /tb_update_matrices/uut/prev_frame_r5
add wave -noupdate /tb_update_matrices/uut/prev_frame_r6
add wave -noupdate /tb_update_matrices/uut/curr_frame_r2
add wave -noupdate /tb_update_matrices/uut/curr_frame_r3
add wave -noupdate /tb_update_matrices/uut/curr_frame_r4
add wave -noupdate /tb_update_matrices/uut/curr_frame_r5
add wave -noupdate /tb_update_matrices/uut/curr_frame_r6
add wave -noupdate /tb_update_matrices/uut/valid_out
add wave -noupdate /tb_update_matrices/uut/layer_id_out
add wave -noupdate /tb_update_matrices/uut/matrix_G11_out
add wave -noupdate /tb_update_matrices/uut/matrix_G12_out
add wave -noupdate /tb_update_matrices/uut/matrix_G22_out
add wave -noupdate /tb_update_matrices/uut/vector_h1_out
add wave -noupdate /tb_update_matrices/uut/vector_h2_out
add wave -noupdate /tb_update_matrices/uut/delta_b_x_s1
add wave -noupdate /tb_update_matrices/uut/delta_b_y_s1
add wave -noupdate /tb_update_matrices/uut/matrix_A11_s1
add wave -noupdate /tb_update_matrices/uut/matrix_A22_s1
add wave -noupdate /tb_update_matrices/uut/matrix_A12_s1
add wave -noupdate /tb_update_matrices/uut/layer_id_s1
add wave -noupdate /tb_update_matrices/uut/valid_s1
add wave -noupdate /tb_update_matrices/uut/A11_squared_s2
add wave -noupdate /tb_update_matrices/uut/A22_squared_s2
add wave -noupdate /tb_update_matrices/uut/A12_squared_s2
add wave -noupdate /tb_update_matrices/uut/h1_term1_s2
add wave -noupdate /tb_update_matrices/uut/h1_term2_s2
add wave -noupdate /tb_update_matrices/uut/h2_term1_s2
add wave -noupdate /tb_update_matrices/uut/h2_term2_s2
add wave -noupdate /tb_update_matrices/uut/A_trace_sum_s2
add wave -noupdate /tb_update_matrices/uut/matrix_A12_delay_s2
add wave -noupdate /tb_update_matrices/uut/layer_id_s2
add wave -noupdate /tb_update_matrices/uut/valid_s2
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {36084289 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1000
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {36084050 ps} {36085050 ps}
