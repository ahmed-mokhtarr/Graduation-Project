onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/clk
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/rst_n
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/pixel_v
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/pixel_in
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/x_count
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/y_count
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/tile_x
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/tile_y
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/tile_idx
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/tile_x_count
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/tile_y_count
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/pixel_out
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/pixel_v_out
add wave -noupdate -expand -group tile -radix unsigned /bilinear_interpolation_tb/u_dut/tile_dut/currnet_tile_idx
add wave -noupdate -expand -group bram1 -radix unsigned /bilinear_interpolation_tb/u_dut/bram_dut/clk
add wave -noupdate -expand -group bram1 -radix unsigned /bilinear_interpolation_tb/u_dut/bram_dut/we
add wave -noupdate -expand -group bram1 -radix unsigned /bilinear_interpolation_tb/u_dut/bram_dut/wr_addr
add wave -noupdate -expand -group bram1 -radix unsigned /bilinear_interpolation_tb/u_dut/bram_dut/wr_data
add wave -noupdate -expand -group bram1 -radix unsigned /bilinear_interpolation_tb/u_dut/bram_dut/rd_addr
add wave -noupdate -expand -group bram1 -radix unsigned /bilinear_interpolation_tb/u_dut/bram_dut/rd_data
add wave -noupdate -expand -group bram1 -radix unsigned /bilinear_interpolation_tb/u_dut/bram_dut/ram
add wave -noupdate -expand -group bram1 -radix unsigned /bilinear_interpolation_tb/u_dut/bram_dut/i
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/clk
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/rst_n
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/pixel_v
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/pixel_in
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/tile_idx
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/wr_bram_addr
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/wr_bram_data
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/wr_bram_en
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/rd_bram_addr
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/rd_bram_data
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/hist_ready
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/pixel_count
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/valid_reg
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/addr_reg
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/fwd_valid
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/fwd_addr
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/fwd_wr_data
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/fwd_valid_2
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/fwd_addr_2
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/fwd_wr_data_2
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/conflict_flag_1
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/conflict_flag_2
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/rd_data
add wave -noupdate -expand -group histogram_generation -radix unsigned /bilinear_interpolation_tb/u_dut/histogram_dut/curr_addr
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/clk
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/rst_n
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/hist_ready
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/wr_bram_addr
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/wr_bram_data
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/wr_bram_en
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/rd_bram_addr
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/rd_bram_data
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/clip_ready
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/clipping_mode
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/tile_cnt
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/tile_bin_cnt
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/excess_total
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/excess_per_bin
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/excess_per_bin_reminder
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/remainder_acc
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/next_acc
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/prev_bin
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/current_write_addr
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/next_tile_id
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/current_state
add wave -noupdate -expand -group clipping -radix unsigned /bilinear_interpolation_tb/u_dut/clipping_dut/next_state
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/clk
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/rst_n
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/clip_ready
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/tile_idx
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/wr_bram_addr
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/wr_bram_data
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/wr_bram_en
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/rd_bram_addr
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/rd_bram_data
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/cdf_ready
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/cdf_mode
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/tile_bin_cnt
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/acc_sum
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/multiply_result
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/cdf_result
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/current_state
add wave -noupdate -expand -group cdf -radix unsigned /bilinear_interpolation_tb/u_dut/cdf_dut/next_state
add wave -noupdate -expand -group counter -radix unsigned /bilinear_interpolation_tb/u_dut/counter_dut/clk
add wave -noupdate -expand -group counter -radix unsigned /bilinear_interpolation_tb/u_dut/counter_dut/rst_n
add wave -noupdate -expand -group counter -radix unsigned /bilinear_interpolation_tb/u_dut/counter_dut/pixel_v
add wave -noupdate -expand -group counter -radix unsigned /bilinear_interpolation_tb/u_dut/counter_dut/pixel_in
add wave -noupdate -expand -group counter -radix unsigned /bilinear_interpolation_tb/u_dut/counter_dut/x_count
add wave -noupdate -expand -group counter -radix unsigned /bilinear_interpolation_tb/u_dut/counter_dut/y_count
add wave -noupdate -expand -group counter -radix unsigned /bilinear_interpolation_tb/u_dut/counter_dut/pixel_out
add wave -noupdate -expand -group counter -radix unsigned /bilinear_interpolation_tb/u_dut/counter_dut/pixel_v_out
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/clk
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/rst_n
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/pixel_in
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/pixel_v
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/x_count
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/y_count
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/rd_bram_addr
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/tl_idx
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/tr_idx
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/bl_idx
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/br_idx
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/tl_data
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/tr_data
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/bl_data
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/br_data
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/pixel_out
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/pixel_v_out
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/calc_x
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/calc_y
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/v_s1
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/left_col
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/right_col
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/top_row
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/bot_row
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/dx
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/dy
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/x_weight
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/y_weight
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/v_s2
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/TL_reg
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/TR_reg
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/BL_reg
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/BR_reg
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/x_w_s3
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/y_w_s3
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/v_s3
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/interp_x_top
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/interp_x_bot
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/y_w_s4
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/v_s4
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/interp_y_final
add wave -noupdate -expand -group interpolation -radix unsigned /bilinear_interpolation_tb/u_dut/interpolation_dut/v_s5
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {3209849330 ps} 0}
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
WaveRestoreZoom {46391388 ps} {19530774138 ps}
