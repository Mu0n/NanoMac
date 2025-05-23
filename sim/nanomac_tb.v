// nanomacxs simulation top

module nanomac_tb
  (
   input	    clk, // 16/32mhz
   input	    reset,
   output reg [2:0] phase, 

   // serial output, mainly for diagrom
   output	    uart_tx,

   // video
   output	    hs_n,
   output	    vs_n,
   output	    pix,
   output [10:0]    audio,

   output	    _romOE,
   output [17:0]    romAddr, 
   input [15:0]	    romData, 

   // keyboard
   input	    kbd_strobe,
   input [7:0]	    kbd_data, 
   
   // interface to sd card
   input [31:0]	    image_size, // length of image file
   input [1:0]	    image_mounted,
   output [10:0]    sdc_lba,
   output [1:0]	    sdc_rd,
   input	    sdc_done,
   input	    sdc_busy,
   input [7:0]	    sdc_data,
   input	    sdc_data_en,
   input [8:0]	    sdc_addr,

   // sdram interface
   output	    sd_clk, // sd clock
   output	    sd_cke, // clock enable
   output [31:0]    sd_data_out, // 32 bit bidirectional data bus
   input [31:0]	    sd_data_in,
   output [10:0]    sd_addr, // 11 bit multiplexed address bus
   output [3:0]	    sd_dqm, // two byte masks
   output [1:0]	    sd_ba, // two banks
   output	    sd_cs, // a single chip select
   output	    sd_we, // write enable
   output	    sd_ras, // row address select
   output	    sd_cas, // columns address select
   
   // interface to sdram controller
   output	    sdram_oe,
   output	    sdram_we,
   output [1:0]	    sdram_ds,
   output [20:0]    ram_addr,
   output [15:0]    sdram_din,
   input [15:0]	    sdram_do
   );

wire		    ram_ready;   
wire [15:0]	    sdram_dout;
   
sdram sdram (
             .clk(clk),               // sdram is accessed at 16MHz
             .reset_n(!reset),        // init signal after FPGA config to initialize RAM
	     
	     .sd_clk(sd_clk),         // sd clock
             .sd_cke(sd_cke),         // clock enable
             .sd_data(sd_data_out),   // 32 bit bidirectional data bus
             .sd_data_in(sd_data_in),
             .sd_addr(sd_addr),       // 11 bit multiplexed address bus
             .sd_dqm(sd_dqm),         // four byte masks
             .sd_ba(sd_ba),           // four banks
             .sd_cs(sd_cs),           // a single chip select
             .sd_we(sd_we),           // write enable
             .sd_ras(sd_ras),         // row address select
             .sd_cas(sd_cas),         // columns address select

             // cpu/chipset interface
             .ready(ram_ready),       // ram is ready and has been initialized
             .phase(phase),           // bus cycle phase to sync to
             .din(sdram_din),         // data input from chipset/cpu
             .dout(sdram_dout),       // data output to chipset/cpu
             .addr({1'b0, ram_addr}), // 22 bit word address
             .ds(~sdram_ds),          // upper/lower data strobe
             .oe(sdram_oe),           // cpu/chipset requests read/wrie
             .we(sdram_we)            // cpu/chipset requests write
);   

macplus macplus (
        //Master input clock
        .CLKIN(clk),

        //Async reset from top-level module.
        //Can be used as initial reset.
        .RESET(reset || !ram_ready),

        .pixelOut(pix),
        .hsync(hs_n),
        .vsync(vs_n),

        .audio(audio),

	.configROMSize(1'b1),       // 64k or 128K ROM
	.configRAMSize(2'd0),       // 128k, 512k, 1MB or 4MB
	.configMachineType(1'b0),   // Plus, SE

        .leds(),

        //ADC
        .ADC_BUS(),

        //MOUSE + Keyboard
        .MOUSE(5'b11111),
        .kbd_strobe(kbd_strobe),
        .kbd_data(kbd_data),

        //SD-SPI
        .SD_SCK(),
        .SD_MOSI(),
        .SD_MISO(),
        .SD_CS(),
        .SD_CD(),

        // interface to sd card
	.sdc_image_size( image_size),
	.sdc_image_mounted( image_mounted ),
	.sdc_lba     ( sdc_lba     ),
	.sdc_rd      ( sdc_rd      ),
	.sdc_busy    ( sdc_busy    ),
	.sdc_done    ( sdc_done    ),
	.sdc_data    ( sdc_data    ),
	.sdc_data_en ( sdc_data_en ),
	.sdc_addr    ( sdc_addr    ),
	 
	._romOE(_romOE),
	.romAddr(romAddr),
	.romData(romData),
		 
         // interface to (sd)ram
	.busPhase(phase),
	.ram_addr(ram_addr),
	.sdram_din(sdram_din),
	.sdram_ds(sdram_ds),
	.sdram_we(sdram_we),
	.sdram_oe(sdram_oe),
//	.sdram_do(sdram_do),  // sdram_do (sim sram), sdram_dout = (sim sdram)
	.sdram_do(sdram_dout),
 
        .UART_CTS(),
        .UART_RTS(),
        .UART_RXD(),
        .UART_TXD(),
        .UART_DTR(),
        .UART_DSR()
);

//video_analyzer video_analyzer 
//(
// .clk(clk),
// .hs(hs_n),
// .vs(vs_n),
// .pal(),
// .interlace(),
// .vreset()
// );   
   
endmodule
