
VERDI_TOOL   := gtkwave
SIM_TOOL     := iverilog
#SIM_TOOL     := verilator
SIM_OPTIONS  := 


SIM_APP  ?= tiny_qspi_apb
SIM_TOP  := $(SIM_APP)_tb

ifeq (${SIM_TOOL},verilator)
    WAVE_CFG ?= +define+WAVE_ON --trace-fst +define+WAVE_NAME=\"$(SIM_TOP).fst\"
    RUN_ARGS ?=
    RUN_ARGS += ${WAVE_CFG} --binary --top ${SIM_TOP}
    RUN_ARGS += --coverage 
    RUN_ARGS += -Wno-fatal
else
    WAVE_CFG ?= DWAVE_ON
    RUN_ARGS ?=
    RUN_ARGS += -${WAVE_CFG}
    RUN_ARGS += -DWAVE_NAME=\"$(SIM_TOP).fst\"
endif

comp:
	@mkdir -p build
	cd build && (${SIM_TOOL} ../src/*.v ../tb/*.v ../model/*.v  $(RUN_ARGS)) 
    #../model/*.sv

ifeq (${SIM_TOOL},verilator)
run: comp
	cd build && ./obj_dir/V${SIM_TOP}
else
run: comp
	cd build && vvp ./a.out -fst 
endif

wave:
	${VERDI_TOOL} build/$(SIM_TOP).fst &

clean:
	rm -rf build

.PHONY: comp run wave
