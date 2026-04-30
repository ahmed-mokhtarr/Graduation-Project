onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/clk
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/rst_n
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/s_axis_tdata
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/s_axis_tvalid
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/s_axis_tready
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/s_axis_tlast
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/s_axis_tuser
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/corner_valid
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/corner_col
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/corner_row
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/corner_score
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/f_out
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/corner_cnt
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/pix_idx
add wave -noupdate -expand -group TB -radix unsigned /fast_top_tb/col_idx
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/clk
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/rst_n
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/s_axis_tdata
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/s_axis_tvalid
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/s_axis_tready
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/s_axis_tlast
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/s_axis_tuser
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/pixel_data
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/pixel_valid
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/col_cnt
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/row_cnt
add wave -noupdate -expand -group AXI -radix unsigned /fast_top_tb/u_dut/u_axis/beat
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/clk
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/rst_n
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/din
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/din_valid
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/col_cnt_in
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/row_cnt_in
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/circle
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/center_pixel
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/window_valid
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/out_col
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/out_row
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_out_0
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_out_1
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_out_2
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_out_3
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_out_4
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_out_5
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_vld_0
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_vld_1
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_vld_2
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_vld_3
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_vld_4
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/lb_vld_5
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/tap_bus
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/tap_valid
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/rr
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/cc
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/in_col_range
add wave -noupdate -expand -group ROW_BUFFER+WINDOW -radix unsigned /fast_top_tb/u_dut/u_rwe/in_row_range
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/Ip
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/circle
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/is_corner
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/upper_raw
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/lower_raw
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/upper
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/lower
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/px
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/bright
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/dark
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/found_bright
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/found_dark
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/i
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/j
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/run_b
add wave -noupdate -expand -group CIRCLE_TEST -radix unsigned /fast_top_tb/u_dut/u_circle/run_d
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/Ip
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/circle
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/score
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/upper_raw
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/lower_raw
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/upper
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/lower
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/px
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/bc
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/dc
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/sum_bright
add wave -noupdate -expand -group SCORE -radix unsigned /fast_top_tb/u_dut/u_score/sum_dark
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/clk
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/rst_n
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/score_in
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/score_valid
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/col_in
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/row_in
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/corner_valid
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/corner_score
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/corner_col
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/corner_row
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/lb1_out
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/lb2_out
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/lb1_valid
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/lb2_valid
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/center
add wave -noupdate -expand -group NMS -radix unsigned /fast_top_tb/u_dut/u_nms/is_local_max
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/clk
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/din
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/din_valid
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/dout
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/dout_valid
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/full
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/mem
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/ptr
add wave -noupdate -expand -group line_buffer1 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb0/rst_n
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/clk
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/din
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/din_valid
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/dout
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/dout_valid
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/tap_r
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/full
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/mem
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/ptr
add wave -noupdate -expand -group line_buffer_2 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb1/rst_n
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/clk
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/din
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/din_valid
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/dout
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/dout_valid
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/full
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/mem
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/ptr
add wave -noupdate -expand -group line_buffer6 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb5/rst_n
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/clk
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/din
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/din_valid
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/dout
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/dout_valid
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/full
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/mem
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/ptr
add wave -noupdate -expand -group line_buffer5 -radix unsigned /fast_top_tb/u_dut/u_rwe/u_lb4/rst_n
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {76711002 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 244
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {76662688 ps} {77475857 ps}
