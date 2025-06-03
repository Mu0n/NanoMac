module addrController (
	// clocks:
	input	      clk,
	input	      clk8_en_p,
	input	      clk8_en_n,

	input	      videoBusControl,
	input	      cpuBusControl,
	input	      cycleReady,
			  
	// system config:
	input [1:0]   configROMSize, // 0 = 64K ROM, 1 = 128K ROM, 2 = 256K ROM
	input [1:0]   configRAMSize, // 0 = 128K, 1 = 512K, 2 = 1MB, 3 = 4MB RAM

	// 68000 CPU memory interface:
	input [23:1]  cpuAddr,
	input	      _cpuUDS,
	input	      _cpuLDS,
	input	      _cpuRW, 
	input	      _cpuAS,
	
	// RAM/ROM:
	output [17:0] romAddr,
	output [20:0] ramAddr,
	output	      _memoryUDS,
	output	      _memoryLDS, 
	output	      _romOE,
	output	      _ramOE, 
	output	      _ramWE, 
	
	// peripherals:
	output	      selectSCSI,
	output	      selectSCC,
	output	      selectIWM,
	output	      selectVIA,
	output	      selectRAM,
	output	      selectROM,
	output	      selectSEOverlay,
	
	// video:
	output	      hsync,
	output	      vsync,
	output	      _hblank,
	output	      _vblank,
	output	      loadPixels,
	input	      vid_alt,
		
	input	      snd_alt,
	output	      loadSound,
		
	// misc
	input	      memoryOverlayOn,
	output	      refresh	      
);

	// -------------- audio engine (may be moved into seperate module) ---------------

        // A new audio byte is read at the end of each hblank. Each hblank thus raises
        // the sndReq which in turn activates the request for a full video cycle to be
        // used for audio transfer
        reg sndReq, sndReqCycle;   
	assign loadSound = videoBusControl & sndReqCycle;

	reg [20:0] audioAddr; 	
	reg vblankD, hblankD;
	always @(posedge clk) begin
	        if(cycleReady) begin
	                sndReqCycle <= sndReq;	   
	                if(loadSound) begin
				sndReq <= 1'b0;
				audioAddr <= audioAddr + 21'd1;
			end
		end
	   
		if(clk8_en_p) begin	   
			vblankD <= _vblank;
			hblankD <= _hblank;
		
			// falling adge of _vblank = begin of vblank phase
			if(vblankD && !_vblank)
				audioAddr <= snd_alt?21'h1FD080:21'h1FFE80;
		        // falling edge of _hblank = audio cycle
			else if(hblankD && !_hblank)
			        sndReq <= 1'b1; // request next audio byte
		   
		end
	end

	// interconnects
	wire [20:0] videoAddr;
	
        // cpu is allowed to access rom anytime
        assign _romOE = ~(selectROM && _cpuRW);

        // ram is being used for video or audio access
        wire va_ram_access = videoBusControl && (loadPixels || loadSound);   
        // TODO: This needs to make sure that the CPU actually uses the cycle. Otherwise write might not work
        wire cpu_ram_access = selectRAM & (cpuBusControl || (videoBusControl && !loadPixels && !loadSound));   

	assign _ramOE = ~((cpu_ram_access &&  _cpuRW) || va_ram_access);
	assign _ramWE = ~( cpu_ram_access && !_cpuRW);
	
	assign _memoryUDS = va_ram_access?1'b0:_cpuUDS;
	assign _memoryLDS = va_ram_access?1'b0:_cpuLDS;

        // three sources may address ram: video, audio or CPU
	wire [20:0] addrMux = loadPixels?videoAddr:loadSound?audioAddr:cpuAddr[21:1];

	// simulate smaller RAM/ROM sizes
	assign ramAddr = { configRAMSize != 2'b11   ? 2'b00 : addrMux[20:19],  // force A20/A19 to 0 for all but 4MB RAM access
			   configRAMSize[1] == 1'b0 ?  1'b0 :    addrMux[18],  // force A18 to 0 for 128K or 512K RAM access
			   configRAMSize == 2'b00   ? 2'b00 : addrMux[17:16],  // force A17/A16 to 0 for 128K RAM access
			   addrMux[15:0] };
   
        assign romAddr = { configROMSize != 2'b11 ? 1'b0 : cpuAddr[18],  // force A18 to 0 for 64K/128K/256K ROM access
			   configROMSize == 2'b01 ? 1'b0 :               // force A17 to 0 for 128K ROM access
			   configROMSize == 2'b00 ? 1'b1 : cpuAddr[17],  // force A17 to 1 for 64K ROM access (64K ROM image is at $20000)
			   configROMSize == 2'b00 ? 1'b0 : cpuAddr[16],  // force A16 to 0 for 64K ROM access
			   cpuAddr[15:1] };   
    
	// address decoding
	addrDecoder ad(
		.configROMSize(configROMSize),
		.address(cpuAddr),
		._cpuAS(_cpuAS),
		.memoryOverlayOn(memoryOverlayOn),
		.selectRAM(selectRAM),
		.selectROM(selectROM),
		.selectSCSI(selectSCSI),
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.selectSEOverlay(selectSEOverlay));

	// video
	videoTimer vt(
		.clk(clk),
		.clk8_en_p(clk8_en_p),
		.clk8_en_n(clk8_en_n),
		.videoCycle(videoBusControl), 
		.vid_alt(vid_alt),
		.videoAddr(videoAddr), 
		.hsync(hsync), 
		.vsync(vsync), 
		._hblank(_hblank),
		._vblank(_vblank), 
		.refresh(refresh), 
		.loadPixels(loadPixels));
		
endmodule
