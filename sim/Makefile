#
# Makefile
#

PRJ=nanomac

OBJ_DIR=obj_dir

# the original fx68k won't simulate. Thus we use this special version for simulation
FX68K_DIR=./fx68x_verilator
FX68K_FILES=fx68k.sv fx68kAlu.sv uaddrPla.sv fx68k_MicroRom.v fx68k_NanoRom.v

VERILATOR_DIR=/usr/local/share/verilator/include
VERILATOR_FILES=verilated.cpp verilated_vcd_c.cpp verilated_threads.cpp

NANOMAC_FILES=clocks.v iwm.v addrController.v addrDecoder.v videoTimer.v dataController.sv ncr5380.sv floppy.v rtc.v scc.v videoShifter.v adb.sv floppy_track_encoder.v floppy_track_buffer.v scsi.v uart/rxuart.v uart/txuart.v via6522.v macplus.sv keyboard.v
NANOMAC_DIR=../src/macplus

TANG_FILES=sdram.v
TANG_DIR=../src/tang/nano20k

TB=nanomac_tb

HDL_FILES=$(TB).v $(NANOMAC_FILES:%=$(NANOMAC_DIR)/%) $(FX68K_FILES:%=$(FX68K_DIR)/%) $(TANG_FILES:%=$(TANG_DIR)/%)
HDL_FILES+=$(MISC_FILES:%=$(MISC_DIR)/%) 

EXTRA_CFLAGS = `sdl2-config --cflags` -DVIDEO
EXTRA_LDFLAGS = `sdl2-config --libs` -lSDL2_image

all: $(PRJ)

$(PRJ): $(TB).cpp ${HDL_FILES} Makefile
	verilator -O3 -Wno-fatal --no-timing --trace-fst --threads 1 --trace-underscore  -top-module $(PRJ)_tb $(VERILATOR_FLAGS) -cc ${HDL_FILES} --exe $(TB).cpp -o ../$(PRJ) -CFLAGS "${EXTRA_CFLAGS}" -LDFLAGS "${EXTRA_LDFLAGS}"
	make -j -C ${OBJ_DIR} -f V$(PRJ)_tb.mk

$(PRJ).fst: $(PRJ)
	./$(PRJ)

run: $(PRJ)
	./$(PRJ)

wave: $(PRJ).fst
	gtkwave $(PRJ).gtkw

clean:
	rm -rf obj_dir $(PRJ)
