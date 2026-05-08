onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/clk
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/rst_n
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/curr_layer
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/operation_start
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/flow_data
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/flow_ready
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/flow_rd_en
add wave -noupdate -group output /tb_zoom_in/dut/zoomed_flow_out
add wave -noupdate -group output /tb_zoom_in/dut/zoomed_tvalid
add wave -noupdate -group output /tb_zoom_in/dut/zoomed_tready
add wave -noupdate -group output /tb_zoom_in/dut/zoom_done
add wave -noupdate -group line_buffer /tb_zoom_in/dut/lb_waddr
add wave -noupdate -group line_buffer /tb_zoom_in/dut/lb_raddr
add wave -noupdate -group line_buffer /tb_zoom_in/dut/lb_din
add wave -noupdate -group line_buffer /tb_zoom_in/dut/lb_we
add wave -noupdate -group line_buffer /tb_zoom_in/dut/lb_rdata
add wave -noupdate -expand -group lb_nextrow -radix hexadecimal /tb_zoom_in/dut/lb_nextrow_waddr
add wave -noupdate -expand -group lb_nextrow -radix hexadecimal /tb_zoom_in/dut/lb_nextrow_raddr
add wave -noupdate -expand -group lb_nextrow -radix hexadecimal /tb_zoom_in/dut/lb_nextrow_din
add wave -noupdate -expand -group lb_nextrow -radix hexadecimal /tb_zoom_in/dut/lb_nextrow_we
add wave -noupdate -expand -group lb_nextrow -radix hexadecimal /tb_zoom_in/dut/lb_nextrow_rdata
add wave -noupdate -expand -group lb_nextrow -radix hexadecimal /tb_zoom_in/dut/lb_nextrow_cnt
add wave -noupdate -expand -group lb_nextrow -radix hexadecimal /tb_zoom_in/dut/lb_nextrow_width
add wave -noupdate -expand -group {state and counters} -radix hexadecimal /tb_zoom_in/dut/state
add wave -noupdate -expand -group {state and counters} -radix hexadecimal /tb_zoom_in/dut/x_cnt
add wave -noupdate -expand -group {state and counters} -radix hexadecimal /tb_zoom_in/dut/y_cnt
add wave -noupdate -expand -group {state and counters} -radix hexadecimal /tb_zoom_in/dut/in_width
add wave -noupdate -expand -group {state and counters} -radix hexadecimal /tb_zoom_in/dut/in_height
add wave -noupdate -expand -group pre_grid -radix hexadecimal /tb_zoom_in/dut/live_reg
add wave -noupdate -expand -group pre_grid -radix hexadecimal /tb_zoom_in/dut/buff_reg
add wave -noupdate -expand -group pre_grid -radix hexadecimal /tb_zoom_in/dut/last_line
add wave -noupdate -expand -group pre_grid -radix hexadecimal /tb_zoom_in/dut/live
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/out_00_dx
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_10_dy
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/out_00_dy
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_10_dx
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_01_dx
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_01_dy
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_11_dx
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_11_dy
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_01_dx_last_col
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_01_dy_last_col
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_11_dx_last_col
add wave -noupdate -expand -group GRID -radix hexadecimal /tb_zoom_in/dut/sum_11_dy_last_col
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/gen0_ready
add wave -noupdate -radix unsigned /tb_zoom_in/pixel_tx_idx
add wave -noupdate -radix hexadecimal /tb_zoom_in/dut/u_line_buffer_nextrow/ram
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {8251332 ps} 0}
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
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits us
update
WaveRestoreZoom {7182501 ps} {7334613 ps}
