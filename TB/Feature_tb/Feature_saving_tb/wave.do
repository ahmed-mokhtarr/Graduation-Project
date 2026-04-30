onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group TB /fast_save_tb/bram_col
add wave -noupdate -expand -group TB /fast_save_tb/bram_row
add wave -noupdate -expand -group TB /fast_save_tb/clk
add wave -noupdate -expand -group TB /fast_save_tb/col_idx
add wave -noupdate -expand -group TB /fast_save_tb/corner_cnt
add wave -noupdate -expand -group TB /fast_save_tb/corner_col
add wave -noupdate -expand -group TB /fast_save_tb/corner_row
add wave -noupdate -expand -group TB /fast_save_tb/corner_score
add wave -noupdate -expand -group TB /fast_save_tb/corner_valid
add wave -noupdate -expand -group TB /fast_save_tb/expected_count
add wave -noupdate -expand -group TB /fast_save_tb/f_out
add wave -noupdate -expand -group TB /fast_save_tb/fail_cnt
add wave -noupdate -expand -group TB /fast_save_tb/frame_done
add wave -noupdate -expand -group TB /fast_save_tb/frame_done_seen
add wave -noupdate -expand -group TB /fast_save_tb/pass_cnt
add wave -noupdate -expand -group TB /fast_save_tb/pix_idx
add wave -noupdate -expand -group TB /fast_save_tb/pixel_mem
add wave -noupdate -expand -group TB /fast_save_tb/prev_feature_count
add wave -noupdate -expand -group TB /fast_save_tb/read_addr
add wave -noupdate -expand -group TB /fast_save_tb/read_data
add wave -noupdate -expand -group TB /fast_save_tb/read_en
add wave -noupdate -expand -group TB /fast_save_tb/rst_n
add wave -noupdate -expand -group TB /fast_save_tb/rtl_corners_col
add wave -noupdate -expand -group TB /fast_save_tb/rtl_corners_row
add wave -noupdate -expand -group TB /fast_save_tb/rtl_corners_score
add wave -noupdate -expand -group TB /fast_save_tb/s_axis_tdata
add wave -noupdate -expand -group TB /fast_save_tb/s_axis_tlast
add wave -noupdate -expand -group TB /fast_save_tb/s_axis_tready
add wave -noupdate -expand -group TB /fast_save_tb/s_axis_tuser
add wave -noupdate -expand -group TB /fast_save_tb/s_axis_tvalid
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/center_pix
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/circle_bus
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/clk
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/col_r
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/col_raw
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/corner_col
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/corner_row
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/corner_score
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/corner_valid
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/frame_done
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/is_corner
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/pix_data
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/pix_valid
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/raw_score
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/row_r
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/row_raw
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/rst_n
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/s_axis_tdata
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/s_axis_tlast
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/s_axis_tready
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/s_axis_tuser
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/s_axis_tvalid
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/score_gated
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/score_r
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/valid_r
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/win_col
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/win_row
add wave -noupdate -height 30 -expand -group FAST_TOP /fast_save_tb/u_dut/u_fast_top/win_valid
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/clk
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/corner_col
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/corner_row
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/corner_valid
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/feature_count
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/frame_done
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/ping_pong_sel
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/prev_feature_count
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/rdata_0
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/rdata_1
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/re_0
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/re_1
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/read_addr
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/read_data
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/read_en
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/rst_n
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/we_0
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/we_1
add wave -noupdate -height 30 -expand -group FEAT_SAVE /fast_save_tb/u_dut/u_feature_saving/write_data
add wave -noupdate -expand -group BRAM_0 /fast_save_tb/u_dut/u_feature_saving/bram_0/clk
add wave -noupdate -expand -group BRAM_0 /fast_save_tb/u_dut/u_feature_saving/bram_0/mem
add wave -noupdate -expand -group BRAM_0 /fast_save_tb/u_dut/u_feature_saving/bram_0/rd_addr
add wave -noupdate -expand -group BRAM_0 /fast_save_tb/u_dut/u_feature_saving/bram_0/rd_data
add wave -noupdate -expand -group BRAM_0 /fast_save_tb/u_dut/u_feature_saving/bram_0/re
add wave -noupdate -expand -group BRAM_0 /fast_save_tb/u_dut/u_feature_saving/bram_0/we
add wave -noupdate -expand -group BRAM_0 /fast_save_tb/u_dut/u_feature_saving/bram_0/wr_addr
add wave -noupdate -expand -group BRAM_0 /fast_save_tb/u_dut/u_feature_saving/bram_0/wr_data
add wave -noupdate -expand -group BRAM_1 /fast_save_tb/u_dut/u_feature_saving/bram_1/clk
add wave -noupdate -expand -group BRAM_1 /fast_save_tb/u_dut/u_feature_saving/bram_1/mem
add wave -noupdate -expand -group BRAM_1 /fast_save_tb/u_dut/u_feature_saving/bram_1/rd_addr
add wave -noupdate -expand -group BRAM_1 /fast_save_tb/u_dut/u_feature_saving/bram_1/rd_data
add wave -noupdate -expand -group BRAM_1 /fast_save_tb/u_dut/u_feature_saving/bram_1/re
add wave -noupdate -expand -group BRAM_1 /fast_save_tb/u_dut/u_feature_saving/bram_1/we
add wave -noupdate -expand -group BRAM_1 /fast_save_tb/u_dut/u_feature_saving/bram_1/wr_addr
add wave -noupdate -expand -group BRAM_1 /fast_save_tb/u_dut/u_feature_saving/bram_1/wr_data
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
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
WaveRestoreZoom {0 ps} {1 ns}
