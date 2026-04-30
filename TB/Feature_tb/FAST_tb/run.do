vlog    rtl/line_buffer.v rtl/axi_stream_slave.v rtl/row_window_extractor.v \
        rtl/fast_circle_test.v rtl/fast_score_calc.v rtl/nms_3x3.v       \
        rtl/fast_top.v

vlog    tb/fast_top_tb.v 


vsim -voptargs=+acc work.fast_top_tb

# add wave *
do wave.do
run -all  