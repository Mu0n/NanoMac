module dataController (
	// clocks:
	input		       clk, // 16 MHz pixel clock
	input		       clk8_en_p,
	input		       clk8_en_n,
	input		       E_rising,
	input		       E_falling,
	
	// system control:
	input		       machineType, // 0 - Mac Plus, 1 - Mac SE
	input		       _systemReset,
	input [1:0]	       floppy_wprot,

	// 68000 CPU control:
	output		       _cpuReset,
	output [2:0]	       _cpuIPL,

	// 68000 CPU memory interface:
	input [15:0]	       cpuDataIn,
	input [3:0]	       cpuAddrRegHi, // A12-A9
	input [2:0]	       cpuAddrRegMid, // A6-A4
	input [1:0]	       cpuAddrRegLo, // A2-A1
	input		       _cpuUDS,
	input		       _cpuLDS, 
	input		       _cpuRW,
	output [15:0]	       cpuDataOut,
	
	// peripherals:
	input		       selectSCSI,
	input		       selectSCC,
	input		       selectIWM,
	input		       selectVIA,
	input		       selectSEOverlay,
	input		       _cpuVMA,
	
	// RAM/ROM:
	input		       videoBusControl, 
	input		       cpuBusControl, 
	input		       cycleReady, 
	input		       romSel,
	input [15:0]	       ramDataIn,
	input [15:0]	       romDataIn,
	output [15:0]	       memoryDataOut,
	
	// mouse:
	input [4:0]	       mouse,
	input		       kbd_strobe,
	input [9:0]	       kbd_data, 
	
	// serial:
	input		       serialIn, 
	output		       serialOut, 
	input		       serialCTS,
	output		       serialRTS,

	// RTC
	input [32:0]	       timestamp,

	// video:
	output		       pixelOut, 
	input		       _hblank,
	input		       _vblank,
	input		       loadPixels,
	output		       vid_alt,

	// audio
	output [10:0]	       audioOut, // 8 bit audio + 3 bit volume
	output		       snd_alt,
	input		       loadSound,
	
	// misc
	output		       memoryOverlayOn,

	output [1:0]	       diskLED,
		       
        // sd card interface
	input [31:0]	       sdc_img_size,
	input [1:0]	       sdc_img_mounted,
	output [10:0]	       sdc_lba,
	output [1:0]	       sdc_rd,
	output [1:0]	       sdc_wr,
	input		       sdc_done,
	input		       sdc_busy,
	input [7:0]	       sdc_data_in,
	output [7:0]	       sdc_data_out,
	input		       sdc_data_en,
	input [8:0]	       sdc_addr,
 
	// connections to io controller
	input [SCSI_DEVS-1:0]  img_mounted,
	input [31:0]	       img_size,
	output [31:0]	       io_lba[SCSI_DEVS],
	output [SCSI_DEVS-1:0] io_rd,
	output [SCSI_DEVS-1:0] io_wr,
	input [SCSI_DEVS-1:0]  io_ack,
	input [7:0]	       sd_buff_addr,
	input [15:0]	       sd_buff_dout,
	output [15:0]	       sd_buff_din[SCSI_DEVS],
	input		       sd_buff_wr
);
	
	parameter SCSI_DEVS = 2;
	
	// add binary volume levels according to volume setting
	assign audioOut = 
		(snd_vol[0]?audio_x1:11'd0) +
		(snd_vol[1]?audio_x2:11'd0) +
		(snd_vol[2]?audio_x4:11'd0);

	// three binary volume levels *1, *2 and *4, sign expanded
	wire [10:0] audio_x1 = { {3{audio_latch[7]}}, audio_latch };
	wire [10:0] audio_x2 = { {2{audio_latch[7]}}, audio_latch, 1'b0 };
	wire [10:0] audio_x4 = {    audio_latch[7]  , audio_latch, 2'b00};
	
	// read audio data and convert to signed for further volume adjustment
	reg [7:0] audio_latch;
	always @(posedge clk) begin
		if(cycleReady && loadSound) begin
		        if(snd_ena) audio_latch <= 8'h00; // 8'h7f; // when disabled, drive output high
			else  	    audio_latch <= ramDataIn[15:8] - 8'd128;
		end
	end
	
	// CPU reset generation
	// For initial CPU reset, RESET and HALT must be asserted for at least 100ms = 800,000 clocks of clk8
	reg [19:0] resetDelay; // 20 bits = 1 million
	wire isResetting = resetDelay != 0;

	initial begin
		// force a reset when the FPGA configuration is completed
	        resetDelay <= 20'hFFFFF;
	end
	
	always @(posedge clk or negedge _systemReset) begin
		if (_systemReset == 1'b0) begin
`ifdef VERILATOR
			resetDelay <= 20'hFF;
`else
			resetDelay <= 20'hFFFFF;
`endif
		end
		else if (clk8_en_p && isResetting) begin
			resetDelay <= resetDelay - 1'b1;
		end
	end
	assign _cpuReset = isResetting ? 1'b0 : 1'b1;
	
	// interconnects
	wire SEL;
	wire _viaIrq, _sccIrq, sccWReq;
	wire [15:0] viaDataOut;
	wire [15:0] iwmDataOut;
	wire [7:0] sccDataOut;
	wire [7:0] scsiDataOut;
   
        wire mouseY1 = mouse[0];
        wire mouseY2 = mouse[1];
        wire mouseX1 = mouse[2];
        wire mouseX2 = mouse[3];
        wire mouseButton = mouse[4];   
	
	// interrupt control
	assign _cpuIPL = 
		!_viaIrq?3'b110:
		!_sccIrq?3'b101:
		3'b111;
		

	// CPU-side data output mux
	assign cpuDataOut = selectIWM ? iwmDataOut :
			    selectVIA ? viaDataOut :
			    selectSCC ? { sccDataOut, 8'hEF } :
			    selectSCSI ? { scsiDataOut, 8'hEF } :
			    romSel ? romDataIn:
			    ramDataIn;
	
	// Memory-side
	assign memoryDataOut = cpuDataIn;

	// SCSI
	ncr5380 #(SCSI_DEVS) scsi(
		.clk(clk),
		.reset(!_cpuReset),
		.bus_cs(selectSCSI),
		.bus_rs(cpuAddrRegMid),
		.ior(!_cpuUDS),
		.iow(!_cpuLDS),
		.dack(cpuAddrRegHi[0]),   // A9
		.wdata(cpuDataIn[15:8]),
		.rdata(scsiDataOut),

		// connections to io controller
		.img_mounted( img_mounted ),
		.img_size( img_size ),
		.io_lba ( io_lba ),
		.io_rd ( io_rd ),
		.io_wr ( io_wr ),
		.io_ack ( io_ack ),

		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(sd_buff_din),
		.sd_buff_wr(sd_buff_wr)
	);

	// count vblanks, and set 1 second interrupt after 60 vblanks
	reg [5:0] vblankCount;
	reg _lastVblank;
	always @(posedge clk) begin
		if (clk8_en_n) begin
			_lastVblank <= _vblank;
			if (_vblank == 1'b0 && _lastVblank == 1'b1) begin
				if (vblankCount != 59) begin
					vblankCount <= vblankCount + 1'b1;
				end
				else begin
					vblankCount <= 6'h0;
				end
			end
		end
	end
	wire onesec = vblankCount == 59;

	// Mac SE ROM overlay switch
	reg  SEOverlay;
	always @(posedge clk) begin
		if (!_cpuReset)
			SEOverlay <= 1;
		else if (clk8_en_n && selectSEOverlay)
			SEOverlay <= 0;
	end

	// VIA
	wire [2:0] snd_vol;
	wire snd_ena;
	wire driveSel; // internal drive select, 0 - upper, 1 - lower

	wire [7:0] via_pa_i, via_pa_o, via_pa_oe;
	wire [7:0] via_pb_i, via_pb_o, via_pb_oe;
	wire viaIrq;

	reg kbddata_o;
	reg kbdclk;
	wire cb2_i = kbddata_o;
	wire cb2_o, cb2_t;
   
	assign _viaIrq = ~viaIrq;

	//port A
	assign via_pa_i = {sccWReq, ~via_pa_oe[6:0] | via_pa_o[6:0]};
	assign snd_vol = ~via_pa_oe[2:0] | via_pa_o[2:0];
	assign snd_alt = machineType ? 1'b0 : ~(~via_pa_oe[3] | via_pa_o[3]);
	assign driveSel = machineType ? ~via_pa_oe[4] | via_pa_o[4] : 1'b1;
	assign memoryOverlayOn = machineType ? SEOverlay : ~via_pa_oe[4] | via_pa_o[4];
	assign SEL = ~via_pa_oe[5] | via_pa_o[5];
	assign vid_alt = ~via_pa_oe[6] | via_pa_o[6];

	//port B
	assign via_pb_i = {1'b1, {3{machineType}} | {_hblank, mouseY2, mouseX2}, machineType ? _ADBint : mouseButton, 2'b11, rtcdat_o};
	assign snd_ena = ~via_pb_oe[7] | via_pb_o[7];

	assign viaDataOut[7:0] = 8'hEF;

	via6522 via(
		.clock      (clk),
		.rising     (E_rising),
		.falling    (E_falling),
		.reset      (!_cpuReset),

		.addr       (cpuAddrRegHi),
		.wen        (selectVIA && !_cpuVMA && !_cpuRW),
		.ren        (selectVIA && !_cpuVMA &&  _cpuRW),
		.data_in    (cpuDataIn[15:8]),
		.data_out   (viaDataOut[15:8]),

		.phi2_ref   (),

		//-- pio --
		.port_a_o   (via_pa_o),
		.port_a_t   (via_pa_oe),
		.port_a_i   (via_pa_i),

		.port_b_o   (via_pb_o),
		.port_b_t   (via_pb_oe),
		.port_b_i   (via_pb_i),

		//-- handshake pins
		.ca1_i      (_vblank),
		.ca2_i      (onesec),

		.cb1_i      (kbdclk),
		.cb2_i      (cb2_i),
		.cb2_o      (cb2_o),
		.cb2_t      (cb2_t),

		.irq        (viaIrq)
	);

	wire _rtccs   = ~via_pb_oe[2] | via_pb_o[2];
	wire rtcck    = ~via_pb_oe[1] | via_pb_o[1];
	wire rtcdat_i = ~via_pb_oe[0] | via_pb_o[0];
	wire rtcdat_o;

	rtc pram (
		.clk        (clk),
		.reset      (!_cpuReset),
		.timestamp  (timestamp),
		._cs        (_rtccs),
		.ck         (rtcck),
		.dat_i      (rtcdat_i),
		.dat_o      (rtcdat_o)
	);

	wire _ADBint;
	wire ADBST0 = ~via_pb_oe[4] | via_pb_o[4];
	wire ADBST1 = ~via_pb_oe[5] | via_pb_o[5];
	wire ADBListen;

	reg [10:0] kbdclk_count;
	reg kbd_transmitting, kbd_wait_receiving, kbd_receiving;
	reg [2:0] kbd_bitcnt;

	wire kbddat_i = ~cb2_t | cb2_o;
	reg  [7:0] kbd_to_mac;
	reg kbd_data_valid;

	// Keyboard transmitter-receiver
	always @(posedge clk) begin
		if (clk8_en_p) begin
			if ((kbd_transmitting && !kbd_wait_receiving) || kbd_receiving) begin
				kbdclk_count <= kbdclk_count + 1'd1;
				if (kbdclk_count == (machineType ? 8'd80 : 12'd1300)) begin // ~165usec - Mac Plus / faster - ADB
					kbdclk <= ~kbdclk;
					kbdclk_count <= 0;
					if (kbdclk) begin 
						// shift before the falling edge
						if (kbd_transmitting) kbd_out_data <= { kbd_out_data[6:0], kbddat_i };
						if (kbd_receiving) kbddata_o <= kbd_to_mac[7-kbd_bitcnt];
					end
				end
			end else begin
				kbdclk_count <= 0;
				kbdclk <= 1;
			end
		end
	end

	// Keyboard control
	always @(posedge clk) begin
		reg kbdclk_d;
		reg ADBListenD;
		if (!_cpuReset) begin
			kbd_bitcnt <= 0;
			kbd_transmitting <= 0;
			kbd_wait_receiving <= 0;
			kbd_data_valid <= 0;
			ADBListenD <= 0;
		end else if (clk8_en_p) begin
			if (kbd_in_strobe && !machineType) begin
				kbd_to_mac <= kbd_in_data;
				kbd_data_valid <= 1;
			end

			if (adb_dout_strobe && machineType) begin
				kbd_to_mac <= adb_dout;
				kbd_receiving <= 1;
			end

			kbd_out_strobe <= 0;
			adb_din_strobe <= 0;
			kbdclk_d <= kbdclk;

			// Only the Macintosh can initiate communication over the keyboard lines. On
			// power-up of either the Macintosh or the keyboard, the Macintosh is in
			// charge, and the external device is passive. The Macintosh signals that it's
			// ready to begin communication by pulling the keyboard data line low.
			if (!machineType && !kbd_transmitting && !kbd_receiving && !kbddat_i) begin
				kbd_transmitting <= 1;
				kbd_bitcnt <= 0;
			end

			// ADB transmission start
			if (machineType && !kbd_transmitting && !kbd_receiving) begin
				ADBListenD <= ADBListen;
				if (!ADBListenD && ADBListen) begin
					kbd_transmitting <= 1;
					kbd_bitcnt <= 0;
				end
			end

			// The last bit of the command leaves the keyboard data line low; the
			// Macintosh then indicates it's ready to receive the keyboard's response by
			// setting the data line high. 
			if (kbd_wait_receiving && kbddat_i && kbd_data_valid) begin
				kbd_wait_receiving <= 0;
				kbd_receiving <= 1;
				kbd_transmitting <= 0;
			end

			// send/receive bits at rising edge of the keyboard clock
			if (~kbdclk_d & kbdclk) begin
				kbd_bitcnt <= kbd_bitcnt + 1'd1;

				if (kbd_bitcnt == 3'd7) begin
					if (kbd_transmitting) begin
						if (!machineType) begin
							kbd_out_strobe <= 1;
							kbd_wait_receiving <= 1;
						end else begin
							adb_din_strobe <= 1;
							adb_din <= kbd_out_data;
							kbd_transmitting <= 0;
						end
					end
					if (kbd_receiving) begin
						kbd_receiving <= 0;
						kbd_data_valid <= 0;
					end
				end
			end
		end
	end

	// IWM
	iwm i(
		.clk(clk),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
		._reset(_cpuReset),
		.selectIWM(selectIWM),
		._cpuRW(_cpuRW),
		._cpuLDS(_cpuLDS),
		.dataIn(cpuDataIn),
		.cpuAddrRegHi(cpuAddrRegHi),
		.SEL(SEL),
		.driveSel(driveSel),
	        .diskWProt(floppy_wprot),
		.dataOut(iwmDataOut),
		.diskLED(diskLED),
	      
                // interface to sd card
	        .sd_img_size     ( sdc_img_size    ),
	        .sd_img_mounted    ( sdc_img_mounted    ),
	        .sd_lba     ( sdc_lba     ),
	        .sd_rd      ( sdc_rd      ),
	        .sd_wr      ( sdc_wr      ),
	        .sd_busy    ( sdc_busy    ),
	        .sd_done    ( sdc_done    ),
	        .sd_data_in ( sdc_data_in ),
	        .sd_data_out( sdc_data_out),
	        .sd_data_en ( sdc_data_en ),
	        .sd_addr    ( sdc_addr    )
	);

	// SCC
	scc s(
		.clk(clk),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
		.reset_hw(~_cpuReset),
		.cs(selectSCC && (_cpuLDS == 1'b0 || _cpuUDS == 1'b0)),
//		.cs(selectSCC && (_cpuLDS == 1'b0 || _cpuUDS == 1'b0) && cpuBusControl),
//		.we(!_cpuRW),
		.we(!_cpuLDS),
		.rs(cpuAddrRegLo), 
		.wdata(cpuDataIn[15:8]),
		.rdata(sccDataOut),
		._irq(_sccIrq),
		.dcd_a(mouseX1),
		.dcd_b(mouseY1),
		.wreq(sccWReq),
		.txd(serialOut),
		.rxd(serialIn),
		.cts(serialCTS),
		.rts(serialRTS)
		);
				
	// Video
	videoShifter vs(
		.clk(clk), 
		.clk8_en_p(clk8_en_p), 
		.clk8_en_n(clk8_en_n), 
		.dataIn(ramDataIn),
		.loadPixels(loadPixels & cycleReady), 
		.pixelOut(pixelOut));
	
	wire [7:0] kbd_in_data;
	wire kbd_in_strobe;
	reg  [7:0] kbd_out_data;
	reg  kbd_out_strobe;

	keyboard kbd(
		.clk(clk),
		.en(clk8_en_p),
		.reset(~_cpuReset),

	        // interface to external MCU
		.kbd_strobe(kbd_strobe), 
		.kbd_data(kbd_data),

		// interface to MacPlus
		.data_out(kbd_out_data),       // data from mac
		.strobe_out(kbd_out_strobe),
		.data_in(kbd_in_data),         // data to mac
		.strobe_in(kbd_in_strobe)
        );
        
        // TODO: ADB is only used in the SE which is currently not enabled/fully implemented
        // in NanoMac.    
	reg  [7:0] adb_din;
	reg        adb_din_strobe;
	wire [7:0] adb_dout;
	wire       adb_dout_strobe;

	adb adb(
		.clk(clk),
		.clk_en(clk8_en_p),
		.reset(~_cpuReset),
		.st({ADBST1, ADBST0}),
		._int(_ADBint),
		.viaBusy(kbd_transmitting || kbd_receiving),
		.listen(ADBListen),
		.adb_din(adb_din),
		.adb_din_strobe(adb_din_strobe),
		.adb_dout(adb_dout),
		.adb_dout_strobe(adb_dout_strobe),

		.ps2_mouse(25'h00000),
		.ps2_key(12'h000)
	);

endmodule
