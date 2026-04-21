onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /histogram_generation_tb/clk
add wave -noupdate -radix unsigned /histogram_generation_tb/rst_n
add wave -noupdate -radix unsigned /histogram_generation_tb/pixel_v
add wave -noupdate -radix unsigned /histogram_generation_tb/pixel_in
add wave -noupdate -radix unsigned -childformat {{{/histogram_generation_tb/wr_bram_addr[11]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[10]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[9]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[8]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[7]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[6]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[5]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[4]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[3]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[2]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[1]} -radix unsigned} {{/histogram_generation_tb/wr_bram_addr[0]} -radix unsigned}} -subitemconfig {{/histogram_generation_tb/wr_bram_addr[11]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[10]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[9]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[8]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[7]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[6]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[5]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[4]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[3]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[2]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[1]} {-height 15 -radix unsigned} {/histogram_generation_tb/wr_bram_addr[0]} {-height 15 -radix unsigned}} /histogram_generation_tb/wr_bram_addr
add wave -noupdate -radix unsigned /histogram_generation_tb/wr_bram_data
add wave -noupdate -radix unsigned /histogram_generation_tb/wr_bram_en
add wave -noupdate -radix unsigned /histogram_generation_tb/rd_bram_addr
add wave -noupdate -radix unsigned /histogram_generation_tb/hist_ready
add wave -noupdate -expand -group tile_generation -radix unsigned /histogram_generation_tb/u_dut/tile_dut/x_count
add wave -noupdate -expand -group tile_generation -radix unsigned /histogram_generation_tb/u_dut/tile_dut/y_count
add wave -noupdate -expand -group tile_generation -radix unsigned /histogram_generation_tb/u_dut/tile_dut/tile_idx
add wave -noupdate -expand -group tile_generation -radix unsigned /histogram_generation_tb/u_dut/tile_dut/pixel_out
add wave -noupdate -expand -group tile_generation -radix unsigned /histogram_generation_tb/u_dut/tile_dut/pixel_v_out
add wave -noupdate -expand -group bram -radix unsigned /histogram_generation_tb/clk
add wave -noupdate -expand -group bram -radix unsigned /histogram_generation_tb/u_dut/bram_dut/we
add wave -noupdate -expand -group bram -radix unsigned /histogram_generation_tb/u_dut/bram_dut/wr_addr
add wave -noupdate -expand -group bram -radix unsigned /histogram_generation_tb/u_dut/bram_dut/wr_data
add wave -noupdate -expand -group bram -radix unsigned /histogram_generation_tb/u_dut/bram_dut/rd_addr
add wave -noupdate -expand -group bram -radix unsigned /histogram_generation_tb/u_dut/bram_dut/rd_data
add wave -noupdate -expand -group bram -radix unsigned /histogram_generation_tb/u_dut/bram_dut/ram
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/clk
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/pixel_v
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/pixel_in
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/tile_idx
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/wr_bram_addr
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/wr_bram_data
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/wr_bram_en
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/rd_bram_addr
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/rd_bram_data
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/pixel_count
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/valid_reg
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/addr_reg
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/fwd_valid
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/fwd_addr
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/fwd_wr_data
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/fwd_valid_2
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/fwd_addr_2
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/fwd_wr_data_2
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/conflict_flag_1
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/conflict_flag_2
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/rd_data
add wave -noupdate -expand -group histogram_generation -radix unsigned /histogram_generation_tb/u_dut/histogram_dut/curr_addr
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {82669 ps} 0}
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
WaveRestoreZoom {29682 ps} {326506 ps}
