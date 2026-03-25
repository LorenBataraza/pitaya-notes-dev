vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xilinx_vip
vlib questa_lib/msim/xpm
vlib questa_lib/msim/xil_defaultlib
vlib questa_lib/msim/axi_infrastructure_v1_1_0
vlib questa_lib/msim/axi_vip_v1_1_17
vlib questa_lib/msim/processing_system7_vip_v1_0_19
vlib questa_lib/msim/xlconstant_v1_1_9
vlib questa_lib/msim/lib_cdc_v1_0_3
vlib questa_lib/msim/proc_sys_reset_v5_0_15
vlib questa_lib/msim/axis_infrastructure_v1_1_1
vlib questa_lib/msim/axis_broadcaster_v1_1_30
vlib questa_lib/msim/xbip_utils_v3_0_13
vlib questa_lib/msim/axi_utils_v2_0_9
vlib questa_lib/msim/cic_compiler_v4_0_19
vlib questa_lib/msim/axis_combiner_v1_1_29
vlib questa_lib/msim/xlconcat_v2_1_6

vmap xilinx_vip questa_lib/msim/xilinx_vip
vmap xpm questa_lib/msim/xpm
vmap xil_defaultlib questa_lib/msim/xil_defaultlib
vmap axi_infrastructure_v1_1_0 questa_lib/msim/axi_infrastructure_v1_1_0
vmap axi_vip_v1_1_17 questa_lib/msim/axi_vip_v1_1_17
vmap processing_system7_vip_v1_0_19 questa_lib/msim/processing_system7_vip_v1_0_19
vmap xlconstant_v1_1_9 questa_lib/msim/xlconstant_v1_1_9
vmap lib_cdc_v1_0_3 questa_lib/msim/lib_cdc_v1_0_3
vmap proc_sys_reset_v5_0_15 questa_lib/msim/proc_sys_reset_v5_0_15
vmap axis_infrastructure_v1_1_1 questa_lib/msim/axis_infrastructure_v1_1_1
vmap axis_broadcaster_v1_1_30 questa_lib/msim/axis_broadcaster_v1_1_30
vmap xbip_utils_v3_0_13 questa_lib/msim/xbip_utils_v3_0_13
vmap axi_utils_v2_0_9 questa_lib/msim/axi_utils_v2_0_9
vmap cic_compiler_v4_0_19 questa_lib/msim/cic_compiler_v4_0_19
vmap axis_combiner_v1_1_29 questa_lib/msim/axis_combiner_v1_1_29
vmap xlconcat_v2_1_6 questa_lib/msim/xlconcat_v2_1_6

vlog -work xilinx_vip -64 -incr -mfcu  -sv -L axi_vip_v1_1_17 -L processing_system7_vip_v1_0_19 -L xilinx_vip "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/axi_vip_if.sv" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/clk_vip_if.sv" \
"/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm -64 -incr -mfcu  -sv -L axi_vip_v1_1_17 -L processing_system7_vip_v1_0_19 -L xilinx_vip "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"/tools/Xilinx/Vivado/2024.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/tools/Xilinx/Vivado/2024.1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"/tools/Xilinx/Vivado/2024.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -64 -93  \
"/tools/Xilinx/Vivado/2024.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../bd/system/ip/system_pll_0_0/system_pll_0_0_clk_wiz.v" \
"../../../bd/system/ip/system_pll_0_0/system_pll_0_0.v" \

vlog -work axi_infrastructure_v1_1_0 -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work axi_vip_v1_1_17 -64 -incr -mfcu  -sv -L axi_vip_v1_1_17 -L processing_system7_vip_v1_0_19 -L xilinx_vip "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/4d04/hdl/axi_vip_v1_1_vl_rfs.sv" \

vlog -work processing_system7_vip_v1_0_19 -64 -incr -mfcu  -sv -L axi_vip_v1_1_17 -L processing_system7_vip_v1_0_19 -L xilinx_vip "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl/processing_system7_vip_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../bd/system/ip/system_ps_0_0/sim/system_ps_0_0.v" \

vlog -work xlconstant_v1_1_9 -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/e2d2/hdl/xlconstant_v1_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../bd/system/ip/system_const_0_0/sim/system_const_0_0.v" \

vcom -work lib_cdc_v1_0_3 -64 -93  \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/2a4f/hdl/lib_cdc_v1_0_rfs.vhd" \

vcom -work proc_sys_reset_v5_0_15 -64 -93  \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3a26/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -64 -93  \
"../../../bd/system/ip/system_rst_0_0/sim/system_rst_0_0.vhd" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../bd/system/ipshared/6dd9/56ac/axis_red_pitaya_adc.v" \
"../../../bd/system/ip/system_adc_0_0/sim/system_adc_0_0.v" \
"../../../bd/system/ipshared/a929/56ac/axis_gpio_reader.v" \
"../../../bd/system/ip/system_gpio_0_0/sim/system_gpio_0_0.v" \
"../../../bd/system/ipshared/cbe4/8e04/inout_buffer.v" \
"../../../bd/system/ipshared/cbe4/8e04/input_buffer.v" \
"../../../bd/system/ipshared/cbe4/8e04/output_buffer.v" \
"../../../bd/system/ipshared/cbe4/56ac/axi_hub.v" \
"../../../bd/system/ip/system_hub_0_0/sim/system_hub_0_0.v" \
"../../../bd/system/ipshared/1dd6/56ac/port_slicer.v" \
"../../../bd/system/ip/system_slice_0_0/sim/system_slice_0_0.v" \
"../../../bd/system/ip/system_slice_1_0/sim/system_slice_1_0.v" \
"../../../bd/system/ip/system_slice_2_0/sim/system_slice_2_0.v" \
"../../../bd/system/ip/system_slice_3_0/sim/system_slice_3_0.v" \
"../../../bd/system/ip/system_slice_4_0/sim/system_slice_4_0.v" \
"../../../bd/system/ip/system_slice_5_0/sim/system_slice_5_0.v" \
"../../../bd/system/ip/system_slice_6_0/sim/system_slice_6_0.v" \
"../../../bd/system/ip/system_slice_7_0/sim/system_slice_7_0.v" \
"../../../bd/system/ip/system_slice_8_0/sim/system_slice_8_0.v" \

vlog -work axis_infrastructure_v1_1_1 -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl/axis_infrastructure_v1_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../bd/system/ip/system_bcast_0_0/hdl/tdata_system_bcast_0_0.v" \
"../../../bd/system/ip/system_bcast_0_0/hdl/tuser_system_bcast_0_0.v" \

vlog -work axis_broadcaster_v1_1_30 -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/a575/hdl/axis_broadcaster_v1_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../bd/system/ip/system_bcast_0_0/hdl/top_system_bcast_0_0.v" \
"../../../bd/system/ip/system_bcast_0_0/sim/system_bcast_0_0.v" \
"../../../bd/system/ipshared/6820/56ac/axis_variable.v" \
"../../../bd/system/ip/system_rate_0_0/sim/system_rate_0_0.v" \
"../../../bd/system/ip/system_rate_1_0/sim/system_rate_1_0.v" \

vcom -work xbip_utils_v3_0_13 -64 -93  \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/24e7/hdl/xbip_utils_v3_0_vh_rfs.vhd" \

vcom -work axi_utils_v2_0_9 -64 -93  \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/1a81/hdl/axi_utils_v2_0_vh_rfs.vhd" \

vcom -work cic_compiler_v4_0_19 -64 -93  \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/9f7e/hdl/cic_compiler_v4_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -64 -93  \
"../../../bd/system/ip/system_cic_0_0/sim/system_cic_0_0.vhd" \
"../../../bd/system/ip/system_cic_1_0/sim/system_cic_1_0.vhd" \

vlog -work axis_combiner_v1_1_29 -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/962b/hdl/axis_combiner_v1_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../bd/system/ip/system_comb_0_0/sim/system_comb_0_0.v" \
"../../../bd/system/ipshared/cd40/56ac/axis_trigger.v" \
"../../../bd/system/ip/system_trig_0_0/sim/system_trig_0_0.v" \
"../../../bd/system/ipshared/8206/56ac/axis_oscilloscope.v" \
"../../../bd/system/ip/system_scope_0_0/sim/system_scope_0_0.v" \
"../../../bd/system/ip/system_const_1_0/sim/system_const_1_0.v" \
"../../../bd/system/ipshared/127f/56ac/axis_ram_writer.v" \
"../../../bd/system/ip/system_writer_0_0/sim/system_writer_0_0.v" \

vlog -work xlconcat_v2_1_6 -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/6120/hdl/xlconcat_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/3242" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/ec67/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/b28c/hdl" "+incdir+../../../../trigger_interrupts.gen/sources_1/bd/system/ipshared/434f/hdl" "+incdir+/tools/Xilinx/Vivado/2024.1/data/xilinx_vip/include" \
"../../../bd/system/ip/system_concat_0_0/sim/system_concat_0_0.v" \
"../../../bd/system/ip/system_axis_trigger_0_0/sim/system_axis_trigger_0_0.v" \
"../../../bd/system/ip/system_xlconstant_0_0/sim/system_xlconstant_0_0.v" \
"../../../bd/system/ip/system_xlconstant_1_0/sim/system_xlconstant_1_0.v" \
"../../../bd/system/ip/system_axis_broadcaster_1_0/hdl/tdata_system_axis_broadcaster_1_0.v" \
"../../../bd/system/ip/system_axis_broadcaster_1_0/hdl/tuser_system_axis_broadcaster_1_0.v" \
"../../../bd/system/ip/system_axis_broadcaster_1_0/hdl/top_system_axis_broadcaster_1_0.v" \
"../../../bd/system/ip/system_axis_broadcaster_1_0/sim/system_axis_broadcaster_1_0.v" \
"../../../bd/system/ip/system_axis_broadcaster_2_0/hdl/tdata_system_axis_broadcaster_2_0.v" \
"../../../bd/system/ip/system_axis_broadcaster_2_0/hdl/tuser_system_axis_broadcaster_2_0.v" \
"../../../bd/system/ip/system_axis_broadcaster_2_0/hdl/top_system_axis_broadcaster_2_0.v" \
"../../../bd/system/ip/system_axis_broadcaster_2_0/sim/system_axis_broadcaster_2_0.v" \
"../../../bd/system/ip/system_or_gate_0_0/sim/system_or_gate_0_0.v" \
"../../../bd/system/ip/system_comb_0_1/sim/system_comb_0_1.v" \
"../../../bd/system/ip/system_xlconcat_0_0/sim/system_xlconcat_0_0.v" \
"../../../bd/system/ipshared/355b/56ac/axis_counter.v" \
"../../../bd/system/ip/system_axis_counter_0_0/sim/system_axis_counter_0_0.v" \
"../../../bd/system/ip/system_xlconstant_2_0/sim/system_xlconstant_2_0.v" \
"../../../bd/system/sim/system.v" \

vlog -work xil_defaultlib \
"glbl.v"

