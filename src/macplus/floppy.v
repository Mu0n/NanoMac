/* Synchronous 8-bit replica of 3.5 inch floppy disk drive.

	Differences from the true floppy interace at the Mac's DB-19 port:
	True interface has a writeReq control line, only 1-bit readData and writeData, and no clk.
	True interface does not have newByteReady signal. Instead the IWM must watch the data in bit and synchronize with it to
	   determine the timing and framing of bytes.
	
*/

/* Disk register (read):	
	    State-control lines       Register
  CA2    CA1    CA0    SEL    addressed    Information in register

  0      0      0      0      DIRTN        Head step direction (0=toward track 79, 1=toward track 0)
  0      0      0      1      CSTIN        Disk in place (0=disk is inserted)
  0      0      1      0      STEP         Drive head stepping (setting to 0 performs a step, returns to 1 when step is complete)
  0      0      1      1      WRTPRT       Disk locked (0=locked)
  0      1      0      0      MOTORON      Drive motor running (0=on, 1=off)
  0      1      0      1      TKO          Head at track 0 (0=at track 0)
  0      1      1      0      SWITCHED     Disk switched (1=yes?)
  0      1      1      1      TACH         Tachometer (produces 60 pulses for each rotation of the drive motor)
  1      0      0      0      RDDATA0      Read data, lower head, side 0
  1      0      0      1      RDDATA1      Read data, upper head, side 1 
  1      0      1      0      SUPERDR      Drive is a Superdrive (0=no, 1=yes)
  1      1      0      0      SIDES        Single- or double-sided drive (0=single side, 1=double side)
  1      1      0      1      READY        0 = yes
  1      1      1      0      INSTALLED	   0 = yes
  1      1      1      1      DRVIN        400K/800K: Drive installed (0=drive is present), Superdrive: Inserted disk capacity (0=HD, 1=DD)
	
	Disk registers (write):
    Control lines      Register
  CA1    CA0    SEL    addressed    Register function

  0      0      0      DIRTN        Set stepping direction (0=toward track 79, 1=toward track 0)
  0      0      1      SWITCHED	    Reset disk switched flag (writing 1 sets switch flag to 0)
  0      1      0      STEP         Step the drive head one track (setting to 0 performs a step, returns to 1 when step is complete)
  1      0      0      MOTORON      Turn on/off drive motor (0=on, 1=off)
  1      1      0      EJECT        Eject the disk (writing 1 ejects the disk)
	
*/

`define DRIVE_REG_DIRTN		0  /* R/W: step direction (0=toward track 79, 1=toward track 0) */
`define DRIVE_REG_CSTIN		1  /* R: disk in place (1 = no disk) */
	                           /* W: ?? reset disk switch flag ? */
`define DRIVE_REG_STEP		2  /* R: drive head is stepping (1 = complete) */
	                           /* W: 0 = step drive head */
`define DRIVE_REG_WRTPRT	3  /* R: 0 = disk is write-protected */
`define DRIVE_REG_MOTORON	4  /* R/W: 0 = motor on */
`define DRIVE_REG_TK0		5  /* R: 0 = head at track 0 */
`define DRIVE_REG_EJECT		6  /* R: disk switched (1=yes?)*/
	                           /* W: 1 = eject the disk */
`define DRIVE_REG_TACH		7  /* R: tach-o-meter */
`define DRIVE_REG_RDDATA0	8  /* R: activate lower head: side 0 */
`define DRIVE_REG_RDDATA1	9  /* R: activate upper head: side 1 */
`define DRIVE_REG_SUPERDR	10 /* R: drive is a superdrive (0=no, 1=yes) */
`define DRIVE_REG_SIDES		12 /* R: number of sides (0=single, 1=dbl) */
`define DRIVE_REG_READY		13 /* R: drive ready (head loaded) (0=ready) */
`define DRIVE_REG_INSTALLED	14 /* R: drive present (0 = yes ??) */
`define DRIVE_REG_DRVIN		15 /* R: 400K/800k: drive present (0=yes, 1=no), Superdrive: disk capacity (0=HD, 1=DD) */

module floppy
(
	input	      clk,
	input	      cep,
	input	      cen,

	input	      _reset,
	input [2:0]   ca,
	input	      SEL, // HDSEL from VIA
	input	      lstrb, // aka PH3
	input	      _enable, 
	output [7:0]  readData,

        // interface to receive write data from IWM and return decoded
        // sector data to be written into track buffer
	input [7:0]   writeData, 
	input	      writeDataStrobe, 
	output [7:0]  writeDataDecoded,
	output [8:0]  writeAddr,
	output [3:0]  writeSector,
	output	      writeStrobe,

	input	      advanceDriveHead, // prevents overrun when debugging, does not exist on a real Mac!
	output reg    newByteReady,
	input	      insertDisk,
	input	      diskSides,
	output	      diskEject,
	input	      diskWProt,

	output	      motor,
	output	      act,

        output error,
 
        // Interface to track buffer.
	output	      trackSide, // side requested by floppy
	output [6:0]  trackIndex, // index of track requested by floppy
 
	output [13:0] trackAddr,
	input [7:0]   trackData,
	input [3:0]   trackSpt, // sectors on current track
	input	      trackReady
);

reg [15:0] driveRegs;
reg [6:0] driveTrack;
reg driveSide;
reg [7:0] diskDataIn; // incoming byte from the floppy disk
wire stepReady;
	
assign motor = ~driveRegs[`DRIVE_REG_MOTORON];
assign trackIndex = driveTrack;   
assign trackSide = driveSide;   

	// read drive registers
	wire [15:0] driveRegsAsRead = {
		1'b0, // DRVIN = yes
		1'b0, // INSTALLED = yes
		1'b0, // READY = yes
		1'b1, // SIDES = double-sided drive
		1'b0, // UNUSED
		1'b0, // SUPERDR
		1'b0, // RDDATA1
		1'b0, // RDDATA0
		driveRegs[`DRIVE_REG_TACH], // TACH: 60 pules for each rotation of the drive motor
		1'b0, // disk switched?
		~(driveTrack == 7'h00), // TK0: track 0 indicator
		driveRegs[`DRIVE_REG_MOTORON], // motor on
		~diskWProt, // WRTPRT = 0=locked, 1=unlocked
	        stepReady, // 1'b1, // STEP = complete
		driveRegs[`DRIVE_REG_CSTIN], // disk in drive
		driveRegs[`DRIVE_REG_DIRTN] // step direction
	};
   
	wire [7:0] dskReadDataEnc;
	
	reg old_newByteReady;
	always @(posedge clk) old_newByteReady <= newByteReady;
	
	// include track encoder
	floppy_track_codec codec
	(
		.clk		 ( clk ),
		.en		 ( cen ),
		.ready	         ( ~old_newByteReady & newByteReady & trackReady ),

		.rst             ( !_reset ),
		
		.side            ( driveSide ),
		.sides           ( diskSides ),
		.track           ( driveTrack ),

	        // read interface to read data from buffer to encode on the fly
	        .addr            ( trackAddr ),
		.data            ( trackData ),
		.spt             ( trackSpt  ),
		.odata           ( dskReadDataEnc ),
	 
                // write direction (decoding data encoded by mac)
	        .writeData       ( writeData       ),
	        .writeDataStrobe ( writeDataStrobe ),

                .error(error),
	        .writeDataDecoded( writeDataDecoded ),
	        .writeAddr       ( writeAddr        ),
                .writeSector     ( writeSector      ),
                .writeStrobe     ( writeStrobe      )
	);
	
	wire [3:0] driveReadAddr = {ca,SEL};
	
	// a byte is read or written every 128 clocks (2 us per bit * 8 bits = 16 us, @ 8 MHz = 128 clocks)
	// The CPU must poll for data at least this often, or else an overrun will occur.
	reg [6:0] diskDataByteTimer;
	reg [7:0] diskImageData;	
	reg readyToAdvanceHead;
	always @(posedge clk or negedge _reset) begin
		if (_reset == 0) begin		
			driveSide <= 0;
			diskImageData <= 8'h00;
			diskDataIn <= 8'hFF;
			diskDataByteTimer <= 0;
			readyToAdvanceHead <= 1;
			newByteReady <= 1'b0;
		end
		else begin			
			if(cep) begin
			   // at time 0, latch a new byte and advance the drive head
			   if (diskDataByteTimer == 0 && readyToAdvanceHead && diskImageData != 0) begin
			      diskDataIn <= diskImageData;
			      newByteReady <= 1;
			      diskDataByteTimer <= 1;  // make timer run again
			      
			      // clear diskImageData after it's used, so we can tell when we get a new one from the disk	
			      diskImageData <= 0;
			      
			      // for debugging, don't advance the head until the IWM says it's ready
			      readyToAdvanceHead <= 1'b1; // TEMP: treat IWM as always ready
			   end
			   
			   // The iwm data rates is 8MHZ/128 = 16us
			   else begin
			      // a timer governs when the next disk byte will become available
			      diskDataByteTimer <= diskDataByteTimer + 1'b1;
			      
			      newByteReady <= 1'b0;
			      
			      // latch bew byte shortly after it has been requested
			      if (diskDataByteTimer == 1) begin
				 // whenever ACK is received, store the data from the current diskImageAddr 
				 diskImageData <= dskReadDataEnc;
			      end
			      
			      if (advanceDriveHead) begin
				 readyToAdvanceHead <= 1'b1;
			      end
			end

			// switch drive sides if DRIVE_REG_RDDATA0 or DRIVE_REG_RDDATA1 are read
			// TODO: we don't know if this is a true read, since we don't know if IWM is selected or 
			// could be bad if we use this test to flush a cache of encoded disk data
			if (driveReadAddr == `DRIVE_REG_RDDATA0 && lstrb == 1'b0)
				driveSide <= 0;
			if (driveReadAddr == `DRIVE_REG_RDDATA1 && lstrb == 1'b0)
				driveSide <= 1;	
		end
	end
	end

	// create a signal on the falling edge of lstrb
	reg lstrbPrev;
	always @(posedge clk) if(cep) lstrbPrev <= lstrb;

	wire lstrbEdge = lstrb == 1'b0 && lstrbPrev == 1'b1;

        // expand lstrb for some disk activity signal
        reg [15:0] act_cnt;
        assign act = (act_cnt != 0);
        always @(posedge clk) begin
	   if(cep) begin
	      if(lstrbEdge)    act_cnt <= 16'hffff;
	      else if(act_cnt) act_cnt <= act_cnt - 16'd1;
	   end	   
	end

	assign readData = _enable ? 8'hFF :
	                  (driveReadAddr == `DRIVE_REG_RDDATA0 || driveReadAddr == `DRIVE_REG_RDDATA1) ? diskDataIn :
			  { driveRegsAsRead[driveReadAddr], 7'h00 };

	// write drive registers
	wire [2:0] driveWriteAddr = {ca[1:0],SEL};
   
	// DRIVE_REG_DIRTN		0  /* R/W: step direction (0=toward track 79, 1=toward track 0) */
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin		
			driveRegs[`DRIVE_REG_DIRTN] <= 1'b0;
		end 
		else if(cep && _enable == 1'b0 && lstrbEdge == 1'b1 && driveWriteAddr == `DRIVE_REG_DIRTN) begin
			driveRegs[`DRIVE_REG_DIRTN] <= ca[2];
		end
	end


	// DRIVE_REG_CSTIN	1  /* R: disk in place (1 = no disk) */
				   /* W: ?? reset disk switch flag ? */
	// disk in drive indicators
	reg [7:0] ejectIndicatorTimer;
	assign diskEject = (ejectIndicatorTimer != 0);
	
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin		
			driveRegs[`DRIVE_REG_CSTIN] <= 1'b1;
			ejectIndicatorTimer <= 8'd0;
		end 
		else if(cep) begin
			if (_enable == 1'b0 && lstrbEdge == 1'b1 && driveWriteAddr == `DRIVE_REG_EJECT && ca[2]) begin
				// eject the disk
				driveRegs[`DRIVE_REG_CSTIN] <= 1'b1;
				ejectIndicatorTimer <= 8'hFF;
			end
			else if (insertDisk) begin
				// insert a disk
				driveRegs[`DRIVE_REG_CSTIN] <= 1'b0;
			end
			else begin
				if (ejectIndicatorTimer != 0)
					ejectIndicatorTimer <= ejectIndicatorTimer - 8'd1;
			end
		end
	end									
									
	//`define DRIVE_REG_STEP		2  /* R: drive head stepping (1 = complete) */
 						   /* W: 0 = step drive head */
        reg [31:0] stepBusy;
        assign stepReady = stepBusy == 16'd0;   
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin	
			driveTrack <= 0;
		        stepBusy <= 16'd0;
		end 
		else if(cep && _enable == 1'b0 && lstrbEdge == 1'b1 && driveWriteAddr == `DRIVE_REG_STEP && ca[2] == 1'b0) begin
		        stepBusy <= 300000/125;
		   
			if (driveRegs[`DRIVE_REG_DIRTN] == 1'b0 && driveTrack != 7'h4F) begin
				driveTrack <= driveTrack + 1'b1;
			end
			if (driveRegs[`DRIVE_REG_DIRTN] == 1'b1 && driveTrack != 0) begin
				driveTrack <= driveTrack - 1'b1;
			end
		end else if(cep && stepBusy /*> 1 || (stepBusy == 1 && trackReady) */ )
		  stepBusy <= stepBusy - 16'd1;
	   // if(trackReady)
	   //	    stepBusy <= 1'b0;
	end
	
	// DRIVE_REG_MOTORON	4  /* R/W: 0 = motor on */
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin		
			driveRegs[`DRIVE_REG_MOTORON] <= 1'b1;
		end 
		else if (cep && _enable == 1'b0 && lstrbEdge == 1'b1 && driveWriteAddr == `DRIVE_REG_MOTORON) begin
			driveRegs[`DRIVE_REG_MOTORON] <= ca[2];
		end
	end

	// DRIVE_REG_TACH  7  Tachometer (produces 60 pulses for each rotation of the drive motor)
	/* Data from MESS, sonydriv.c:
	   Tracks	RPM   Timing Value
	   00-15:   500   timing value $117B (acceptable range {1135-11E9})
	   16-31:   550   timing value $???? (acceptable range {12C6-138A})
	   32-47:   600   timing value $???? (acceptable range {14A7-157F})
	   48-63:   675   timing value $???? (acceptable range {16F2-17E2})
	   64-79:   750   timing value $???? (acceptable range {19D0-1ADE})
		
		Experimentally determined toggle rates for Plus Too with 8.125 MHz CPU clock:
		TACH Half Period Clocks		Resulting Timing Value
			9996			$117B (4475)
			9122  			$1328 (4904)
			8292  			$1513 (5395)
			7463  			$176A (5994)
			6634			$1A56 (6742)
	*/
	
	reg [13:0] driveTachTimer; 
	reg [13:0] driveTachPeriod;
	
	always @(*) begin
		case (driveTrack[6:4])
			0: // tracks 0-15
				driveTachPeriod <= 9996;
			1: // tracks 16-31
				driveTachPeriod <= 9122;
			2: // tracks 32-47
				driveTachPeriod <= 8292;
			3: // tracks 48-63
				driveTachPeriod <= 7463;
			default: // tracks 64-79
				driveTachPeriod <= 6634;	
		endcase
	end
	
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin		
			driveRegs[`DRIVE_REG_TACH] <= 1'b0;
			driveTachTimer <= 0;
		end 
		else if(cep) begin
			if (driveTachTimer == driveTachPeriod) begin
				driveTachTimer <= 0;
				driveRegs[`DRIVE_REG_TACH] <= ~driveRegs[`DRIVE_REG_TACH];
			end
			else begin
				driveTachTimer <= driveTachTimer + 1'b1;
			end
		end
	end	
endmodule
