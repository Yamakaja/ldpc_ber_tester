source ../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create ldpc_ber_tester
adi_ip_files ldpc_ber_tester [list \
    "../boxmuller/src/boxmuller.vhd" \
    "../boxmuller/src/grng_16.vhd" \
    "../boxmuller/src/lzd.vhd" \
    "../boxmuller/src/output_remapper_fixpt.vhd" \
    "../boxmuller/src/output_remapper_fixpt_pkg.vhd" \
    "../boxmuller/src/pp_fcn.vhd" \
    "../boxmuller/src/pp_fcn_rom_pkg.vhd" \
    "../boxmuller/src/shifter.vhd" \
    "../boxmuller/src/xoroshiro128plus.vhd" \
    "$ad_hdl_dir/library/common/up_axi.v" \
    "ldpc_ber_tester_ber_counter.v" \
    "ldpc_ber_tester_axis_gen.vhd" \
    "ldpc_ber_tester_regmap.v" \
    "ldpc_ber_tester.v"
]

set_property FILE_TYPE {VHDL 2008} [get_files ldpc_ber_tester_axis_gen.vhd]

adi_ip_properties ldpc_ber_tester

adi_ip_add_core_dependencies { \
    analog.com:user:util_cdc:1.0 \
}

# Add multiplier IP

create_ip -name mult_gen -vendor xilinx.com -library ip -version 12.0 -module_name mult_23_23_24
set_property -dict [list \
    CONFIG.PortAWidth {23} \
    CONFIG.PortBWidth {23} \
    CONFIG.Multiplier_Construction {Use_Mults} \
    CONFIG.Use_Custom_Output_Width {true} \
    CONFIG.OutputWidthHigh {45} \
    CONFIG.OutputWidthLow {22} \
    CONFIG.PipeStages {4} \
    CONFIG.ClockEnable {true}] [get_ips mult_23_23_24]

generate_target {all} [get_files ldpc_ber_tester.srcs/sources_1/ip/mult_23_23_24/mult_23_23_24.xci]
export_ip_user_files -of_objects [get_files ldpc_ber_tester.srcs/sources_1/ip/mult_23_23_24/mult_23_23_24.xci] -no_script -sync -force -quiet
ipx::add_file ldpc_ber_tester.srcs/sources_1/ip/mult_23_23_24/mult_23_23_24.xci [ipx::get_file_groups xilinx_anylanguagebehavioralsimulation -of_objects [ipx::current_core]]

foreach {f} [list \
    ldpc_ber_tester.srcs/sources_1/ip/mult_23_23_24/mult_23_23_24.xci       \
    ldpc_ber_tester.gen/sources_1/ip/mult_23_23_24/mult_23_23_24.vho        \
    ldpc_ber_tester.gen/sources_1/ip/mult_23_23_24/mult_23_23_24.veo        \
    ldpc_ber_tester.gen/sources_1/ip/mult_23_23_24/mult_23_23_24_ooc.xdc    \
    ] {                                                                     \
    ipx::add_file $f [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
}

adi_ip_ttcl ldpc_ber_tester "ldpc_ber_tester_constr.ttcl"

set_property display_name "LDPC BER Tester" [ipx::current_core]
set_property description "LDPC Bit-Error-Rate Tester, used to characterize (almost) arbitary LDPC codes using Xilinx' SD-FEC HardIP Cores on the RFSoC series devices" [ipx::current_core]

adi_add_bus "m_axis_ctrl" "master" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  [ list \
    {"m_axis_ctrl_tready" "TREADY"} \
    {"m_axis_ctrl_tvalid" "TVALID"} \
    {"m_axis_ctrl_tdata" "TDATA"}]

adi_add_bus "m_axis_din" "master" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  [ list \
    {"m_axis_din_tready" "TREADY"} \
    {"m_axis_din_tvalid" "TVALID"} \
    {"m_axis_din_tdata" "TDATA"} \
    {"m_axis_din_tlast" "TLAST"} ]

adi_add_bus "s_axis_status" "slave" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  [ list \
    {"s_axis_status_tready" "TREADY"} \
    {"s_axis_status_tvalid" "TVALID"} \
    {"s_axis_status_tdata" "TDATA"}]

adi_add_bus "s_axis_dout" "slave" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  [ list \
    {"s_axis_dout_tready" "TREADY"} \
    {"s_axis_dout_tvalid" "TVALID"} \
    {"s_axis_dout_tdata" "TDATA"} \
    {"s_axis_dout_tlast" "TLAST"} ]

adi_add_bus_clock "data_clk" "m_axis_ctrl:m_axis_din:s_axis_status:s_axis_dout" "data_resetn"

ipx::save_core [ipx::current_core]

