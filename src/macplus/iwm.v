/* IWM 

   Mapped to $DFE1FF - $DFFFFF
	
	The 16 IWM one-bit registers are {8'hDF, 8'b111xxxx1, 8'hFF}:
		0	$0	ca0L		CA0 off (0)
		1	$200	ca0H		CA0 on (1)
		2	$400	ca1L		CA1 off (0)
		3	$600	ca1H		CA1 on (1)
		4	$800	ca2L		CA2 off (0)
		5	$A00	ca2H		CA2 on (1)
		6	$C00	ph3L		LSTRB off (low)
		7	$E00	ph3H		LSTRB on (high)
		8	$1000	mtrOff		LENABLE disk enable off
		9	$1200	mtrOn		ENABLE disk enable on
		10	$1400	intDrive	SELECT select internal drive
		11	$1600	extDrive	SELECT select external drive
		12	$1800	q6L		Q6 off
		13	$1A00	q6H		Q6 on
		14	$1C00	q7L		Q7 off, read register
		15	$1E00	q7H		Q7 on, write register
	
	Notes from IWM manual: Serial data is shifted in/out MSB
	first, with a bit transferred every 2 microseconds.  When
	writing data, a 1 is written as a transition on writeData at a
	bit cell boundary time, and a 0 is written as no transition.
	When reading data, a falling transition within a bit cell
	window is considered to be a 1, and no falling transition is
	considered a 0.  When reading data, the read data register
	will latch the shift register when a 1 is shifted into the
	MSB.  The read data register will be cleared 14 fclk periods
	(about 2 microseconds) after a valid data read takes place-- a
	valid data read being defined as both /DEV being low and D7
	(the MSB) outputting a one from the read data register for at
	least one fclk period.  */

module iwm
(
	input	      clk,
	input	      cep,
	input	      cen,

	input	      _reset,
	input	      selectIWM,
	input	      _cpuRW,
	input	      _cpuLDS, 
	input [15:0]  dataIn,
	input [3:0]   cpuAddr,
	input	      SEL, // from VIA
	input	      driveSel, // internal drive select, 0 - upper, 1 - lower
	input [1:0]   diskWProt, // write protection
	output [15:0] dataOut,

	output [2:0]  diskLED,

        // sd card interface
	input [31:0]  sd_img_size,
	input [1:0]   sd_img_mounted,
	output [10:0] sd_lba,
	output [1:0]  sd_rd,
	output [1:0]  sd_wr,
	input	      sd_done,
	input	      sd_busy,
	input [7:0]   sd_data_in,
	output [7:0]  sd_data_out,
	input	      sd_data_en,
	input [8:0]   sd_addr
);

reg selectExternalDrive;
   
wire [1:0]	      diskEject;   
wire [1:0]	      diskSides;  
		      
wire [1:0]	      insertDisk;   
wire [1:0]	      diskAct;   
wire [1:0]	      diskMotor;

wire [1:0]	      driveMask = selectExternalDrive?2'b10:2'b01;

// light both LEDs permanently while the track buffer is dirty and
// needs to be written back by e.g. ejecting the disk
assign diskLED = { dirty, driveMask & insertDisk & diskAct & diskMotor };  

wire		      errorInt, errorExt;   
   
wire sideInt, sideExt;
wire [6:0] trackInt;  
wire [6:0] trackExt;  

wire	   ready;   
wire	   dirty;   
wire	   readyInt = selectExternalDrive?1'b0:ready;   
wire	   readyExt = selectExternalDrive?ready:1'b0;   

wire [7:0] data;
wire [3:0] spt;      

wire [13:0] addrInt;
wire [13:0] addrExt;
wire [13:0] addr = selectExternalDrive?addrExt:addrInt;

// data written by IWM
reg [7:0] writeData;
reg	  writeDataStrobe;   

// write data converted to decoded sector data
wire [7:0] writeDataDecodedInt, writeDataDecodedExt;   
wire [7:0] writeDataDecoded = selectExternalDrive?writeDataDecodedExt:writeDataDecodedInt;   

wire [8:0] writeAddrInt, writeAddrExt;   
wire [8:0] writeAddr = selectExternalDrive?writeAddrExt:writeAddrInt;   

wire [3:0] writeSectorInt, writeSectorExt;   
wire [3:0] writeSector = selectExternalDrive?writeSectorExt:writeSectorInt;   

wire	   writeStrobeInt, writeStrobeExt;   
wire	   writeStrobe = selectExternalDrive?writeStrobeExt:writeStrobeInt;   

// select signal for a single 8Mhz cycle

// when reading, UDS/LDS is valid with AS. When writing it comes a little later. We need to
// distinguish as on a read this already affects the current read
   
reg	   select0, select, selectIWMD;
always @(posedge clk) begin
  if(cen) begin
     selectIWMD <= selectIWM;
     select0 <= selectIWM && !selectIWMD;
     if(_cpuRW)
       select <= selectIWM && !selectIWMD;
     else
       select <= select0;   // delay select on write one more cycle, so UDS/LDS are active as well
  end
end

// Check for activity for a second. This signal is being used to flush the
// write buffer. It seems preferrable to use the motor on signal. But that
// often seems to stay on (forever?).
reg [31:0] act_cnt;
wire	   activity = act_cnt != 32'd0;
   
always @(posedge clk) begin
   if(!_reset)
     act_cnt <= 32'd0;
   else if( cen ) begin
      if(diskAct != 2'b00)
	act_cnt <= 32'd8_000_000;
      else if(act_cnt != 32'd0)
	act_cnt <= act_cnt - 32'd1;
   end
end
   
// we only need a single track buffer since we also only have
// one iwm which in turn can only access one floppy drive at a time
floppy_track_buffer fb 
    (
     .clk(clk),
     .rst(!_reset),

     .inserted(insertDisk),
     .eject(diskEject),
     .activity(activity),
     .drive(selectExternalDrive),
     .sides(diskSides),
     .side(selectExternalDrive?sideExt:sideInt),
     .track(selectExternalDrive?trackExt:trackInt),
     
     // read direction (encoding data for mac)
     .addr(addr), 
     .data(data),
     .spt(spt),
     .ready(ready),
     .dirty(dirty),

     // write direction (decoding data encoded by mac)
     .writeDataDecoded(writeDataDecoded),
     .writeAddr(writeAddr),
     .writeSector(writeSector),
     .writeStrobe(writeStrobe),
     
     // interface to sd card
     .sd_img_size(sd_img_size),
     .sd_img_mounted(sd_img_mounted),
     
     .sd_lba     ( sd_lba     ),
     .sd_rd      ( sd_rd      ),
     .sd_wr      ( sd_wr      ),
     .sd_busy    ( sd_busy    ),
     .sd_done    ( sd_done    ),
     .sd_data_in ( sd_data_in ),
     .sd_data_out( sd_data_out),
     .sd_data_en ( sd_data_en ),
     .sd_addr    ( sd_addr    )
     );
   
	// IWM state
        reg [2:0] ca;
        reg lstrb;
        reg [7:6] q;
   
	wire advanceDriveHead; // prevents overrun when debugging, does not exit on a real Mac!
	reg [7:0] readDataLatch;
	wire _iwmBusy, _writeUnderrun;

	// floppy disk drives 
        reg  diskEnable;
   
	wire newByteReadyInt;
	wire newByteReadyExt;
	wire newByteReady = selectExternalDrive ? newByteReadyExt : newByteReadyInt;

	wire [7:0] readDataInt;
	wire [7:0] readDataExt;
	wire [7:0] readData = selectExternalDrive ? readDataExt : readDataInt;
	
	floppy floppyInt
	(
		.clk(clk),
		.cep(cep),
		.cen(cen),

		._reset(_reset),
		.ca(ca),
		.SEL(SEL),
		.lstrb(lstrb),
		._enable(~(!selectExternalDrive & diskEnable & driveSel)),

		.writeData(writeData),
		.writeDataStrobe(!selectExternalDrive & writeDataStrobe),
	        .writeDataDecoded( writeDataDecodedInt ),
	        .writeAddr       ( writeAddrInt        ),
                .writeSector     ( writeSectorInt      ),
                .writeStrobe     ( writeStrobeInt      ),

		.readData(readDataInt),
		.advanceDriveHead(advanceDriveHead),
		.newByteReady(newByteReadyInt),
		.insertDisk(insertDisk[0]),
		.diskSides(diskSides[0]),
		.diskEject(diskEject[0]),
		.diskWProt(diskWProt[0]),
	
		.motor        ( diskMotor[0] ),
		.act          ( diskAct[0] ),
	 
		.error        ( errorInt ),

	        .trackSide    ( sideInt  ),
	        .trackIndex   ( trackInt ),
	        .trackReady   ( readyInt ),	 
	        .trackAddr    ( addrInt  ),
	        .trackData    ( data     ),
	        .trackSpt     ( spt      )
	);
		
	floppy floppyExt
	(
		.clk(clk),
		.cep(cep),
		.cen(cen),

		._reset(_reset),
		.ca(ca),
		.SEL(SEL),
		.lstrb(lstrb),
		._enable(~(selectExternalDrive && diskEnable)),

		.writeData(writeData),
		.writeDataStrobe(selectExternalDrive & writeDataStrobe),
	        .writeDataDecoded( writeDataDecodedExt ),
	        .writeAddr       ( writeAddrExt        ),
                .writeSector     ( writeSectorExt      ),
                .writeStrobe     ( writeStrobeExt      ),

		.readData(readDataExt),
		.advanceDriveHead(advanceDriveHead),
		.newByteReady(newByteReadyExt),
		.insertDisk(insertDisk[1]),
		.diskSides(diskSides[1]),
		.diskEject(diskEject[1]),
		.diskWProt(diskWProt[1]),
		
		.motor        ( diskMotor[1] ),
		.act          ( diskAct[1] ),

		.error        ( errorExt ),
	 
	        .trackSide    ( sideExt  ),
	        .trackIndex   ( trackExt ),
	        .trackReady   ( readyExt ),	 
	        .trackAddr    ( addrExt  ),
	        .trackData    ( data     ),
	        .trackSpt     ( spt      )
	);

        // generate a write ready signal	
        reg writeBusy;

        // TODO: Implement underrun
        assign _iwmBusy = !writeBusy; // for writes, a value of 1 here indicates the IWM write buffer is empty
	assign _writeUnderrun = 1'b1;


	reg [4:0] iwmMode;
	/* IWM mode register: S C M H L
 	 S	Clock speed:
			0 = 7 MHz
			1 = 8 MHz
		Should always be 1 for Macintosh.
	 C	Bit cell time:
			0 = 4 usec/bit (for 5.25 drives)
			1 = 2 usec/bit (for 3.5 drives) (Macintosh mode)
	 M	Motor-off timer:
			0 = leave drive on for 1 sec after program turns
			    it off
			1 = no delay (Macintosh mode)
		Should be 0 for 5.25 and 1 for 3.5.
	 H	Handshake protocol:
			0 = synchronous (software must supply proper
			    timing for writing data)
			1 = asynchronous (IWM supplies timing) (Macintosh Mode)
		Should be 0 for 5.25 and 1 for 3.5.
	 L	Latch mode:
			0 = read-data stays valid for about 7 usec
			1 = read-data stays valid for full byte time (Macintosh mode)
		Should be 0 for 5.25 and 1 for 3.5.
	*/

// the IWM registers need to change as early as possible as they influence the
// current transfer already 
// any read/write access to IWM bit registers will change their values
always @(posedge clk) begin
   if (!_reset) begin
      ca <= 3'b000;
      lstrb <= 1'b0;
      diskEnable <= 0;
      selectExternalDrive <= 0;
      q <= 2'b00;
   end else  if(cen) begin
      // latch once lds is low
      if (selectIWM && !_cpuLDS) begin
	 case (cpuAddr[3:1])
	   3'h0: ca[0] <= cpuAddr[0];
	   3'h1: ca[1] <= cpuAddr[0];
	   3'h2: ca[2] <= cpuAddr[0];
	   3'h3: lstrb <= cpuAddr[0];
	   3'h4: diskEnable <= cpuAddr[0];
	   3'h5: selectExternalDrive <= cpuAddr[0];
	   3'h6: q[6] <= cpuAddr[0];
	   3'h7: q[7] <= cpuAddr[0];
	 endcase
      end
   end
end

// read IWM state
assign dataOut = { 8'hBE,
   (q == 2'b00)?readDataLatch:
   (q == 2'b01)?{ readData[7], 1'b0, diskEnable, iwmMode }:
   (q == 2'b10)?{ _iwmBusy, _writeUnderrun, 6'b000000 }:
   8'h00 };   
   
always @(posedge clk or negedge _reset) begin
   if (!_reset) begin		
      iwmMode <= 0;
      writeBusy <= 1'b0;
      writeDataStrobe <= 1'b0;
   end else if(cen) begin
      if(newByteReady) writeBusy <= 1'b0;

      if(!_cpuRW && select && !_cpuLDS) begin
	 // writing to any IWM address modifies state as selected by Q7 and Q6
	 case(q)
	   2'b11: begin // IWM mode register when not enabled (write-only), or (write?) data register when enabled
	      if (diskEnable) begin
		    writeData <= dataIn[7:0];
		    writeDataStrobe <= !writeDataStrobe;
		    writeBusy <= 1'b1;
	      end else begin
		 iwmMode <= dataIn[4:0];
	      end
	   end
	 endcase
      end
   end
end

// Manage incoming bytes from the disk drive
reg [3:0] readLatchClearTimer; 
always @(posedge clk or negedge _reset) begin
   if (!_reset) begin	
      readDataLatch <= 0;
      readLatchClearTimer <= 0;
   end else if(cen) begin
      // a countdown timer governs how long after a data latch read before the latch is cleared
      if (readLatchClearTimer != 0)
	 readLatchClearTimer <= readLatchClearTimer - 4'd1;
      
      // the conclusion of a valid CPU read from the IWM will start the timer to clear the latch
      if (_cpuRW && selectIWM && !_cpuLDS && readDataLatch[7])
	 readLatchClearTimer <= 4'd14; // clear latch 14 clocks after the conclusion of a valid read
      
      // when the drive indicates that a new byte is ready, latch it
      // NOTE: the real IWM must self-synchronize with the incoming data to determine when to latch it
      if (newByteReady)
	readDataLatch <= readData;
      else if (readLatchClearTimer == 4'd1)
	readDataLatch <= 0;
   end
end

assign advanceDriveHead = readLatchClearTimer == 4'd1; // prevents overrun when debugging, does not exist on a real Mac!
endmodule
