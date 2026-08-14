onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/clk
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/rst_n
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/cmd_valid
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/cmd_ready
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/cmd_layer
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/cmd_len
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/cmd_slot
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/slot_addr_0
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/slot_addr_1
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/slot_addr_2
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/slot_addr_3
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L0_rd_en
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L1_rd_en
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L2_rd_en
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L3_rd_en
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L4_rd_en
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L0_dout
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L1_dout
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L2_dout
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L3_dout
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/L4_dout
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_awaddr
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_awlen
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_awsize
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_awburst
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_awvalid
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_awready
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_wdata
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_wlast
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_wvalid
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_wready
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_bvalid
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_bready
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/m_axi_bresp
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/state
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/next_state
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/current_base_addr
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/beats_remaining
add wave -noupdate -expand -group write_axi -radix unsigned /pyramid_top_tb/dut/writer_inst/active_layer
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/clk
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/rst_n
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/s_axis_tdata
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/s_axis_tvalid
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/s_axis_tready
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/s_axis_tuser
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/s_axis_tlast
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/eof_pulse_out
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L0_data
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L0_valid
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L0_full
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L1_data
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L1_valid
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L1_full
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L2_data
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L2_valid
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L2_full
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L3_data
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L3_valid
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L3_full
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L4_data
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L4_valid
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/L4_full
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/eof_pulse_reg
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/x_cnt
add wave -noupdate -expand -group sub_sampler -radix unsigned /pyramid_top_tb/dut/subsampler_inst/y_cnt
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/clk
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/rst_n
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/wr_en
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/din
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/full
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/rd_en
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/dout
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/empty
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/data_count
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/mem
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/wr_ptr
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/rd_ptr
add wave -noupdate -expand -group fifo1 -radix unsigned /pyramid_top_tb/dut/fifo_L0/i
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/clk
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/rst_n
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/wr_en
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/din
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/full
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/rd_en
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/dout
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/empty
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/data_count
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/mem
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/wr_ptr
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/rd_ptr
add wave -noupdate -expand -group fifo2 -radix unsigned /pyramid_top_tb/dut/fifo_L1/i
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/clk
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/rst_n
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/wr_en
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/din
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/full
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/rd_en
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/dout
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/empty
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/data_count
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/mem
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/wr_ptr
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/rd_ptr
add wave -noupdate -expand -group fifo3 -radix unsigned /pyramid_top_tb/dut/fifo_L2/i
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/clk
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/rst_n
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/wr_en
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/din
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/full
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/rd_en
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/dout
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/empty
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/data_count
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/mem
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/wr_ptr
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/rd_ptr
add wave -noupdate -expand -group fifo4 -radix unsigned /pyramid_top_tb/dut/fifo_L3/i
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/clk
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/rst_n
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/wr_en
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/din
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/full
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/rd_en
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/dout
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/empty
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/data_count
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/mem
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/wr_ptr
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/rd_ptr
add wave -noupdate -expand -group fifo5 -radix unsigned /pyramid_top_tb/dut/fifo_L4/i
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/clk
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/rst_n
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/eof_pulse
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/L0_cnt
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/L1_cnt
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/L2_cnt
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/L3_cnt
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/L4_cnt
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/cmd_valid
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/cmd_ready
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/cmd_layer
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/cmd_len
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/cmd_slot
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/axi_bvalid
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/write_valid
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/frame_num
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/current_state
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/next_state
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/idx
add wave -noupdate -expand -group fsm -radix unsigned /pyramid_top_tb/dut/fsm_inst/eof_latched
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {10000 ps} 0}
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
WaveRestoreZoom {0 ps} {309590 ps}
