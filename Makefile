LIBRARY_NAME := ldpc_ber_tester

GENERIC_DEPS += ../common/up_axi.v
GENERIC_DEPS += ldpc_ber_tester_regmap.v
GENERIC_DEPS += ldpc_ber_tester_ber_counter.v
GENERIC_DEPS += ldpc_ber_tester.v
GENERIC_DEPS += ldpc_ber_tester_axis_gen.vhd

XILINX_DEPS += ldpc_ber_tester_ip.tcl
XILINX_DEPS += ldpc_ber_tester_constr.ttcl

XILINX_LIB_DEPS += util_cdc
XILINX_LIB_DEPS += boxmuller

include ../scripts/library.mk
