
VERDI_TOOL   := gtkwave
SIM_TOOL     := iverilog
SIM_OPTIONS  := 


SIM_APP  ?= tiny_qspi_apb
SIM_TOP  := $(SIM_APP)_tb

WAVE_CFG ?= DWAVE_ON
RUN_ARGS ?=
RUN_ARGS += -${WAVE_CFG}
RUN_ARGS += -DWAVE_NAME=\"$(SIM_TOP).vcd\"

comp:
	@mkdir -p build
	cd build && (${SIM_TOOL} ../src/*.v ../tb/*.v ../model/*.v ../model/*.sv $(RUN_ARGS))

run: comp
	cd build && vvp ./a.out

wave:
	${VERDI_TOOL} build/$(SIM_TOP).vcd &

clean:
	rm -rf build

.PHONY: wave clean
