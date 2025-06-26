/* 
  floppy_track_codec.v
 
  Encode a full floppy track from raw sector data on the fly. This reads
  data on the fly from a track buffer.
 */

module floppy_track_codec (
   // system signals
   input	    clk, // clock at which data bytes are delivered via odata
   input	    en,
   input	    ready,
   input	    rst,

   input	    side,
   input	    sides,
   input [6:0]	    track, // current track

   // interface to track buffer
   output [13:0]    addr,
   input [7:0]	    data,
   input [3:0]	    spt, 
   output [7:0]	    odata,

   output reg    error,
			     
   input [7:0]	    writeData,
   input	    writeDataStrobe,
   output reg [7:0] writeDataDecoded,
   output reg [8:0] writeAddr,
   output reg [3:0] writeSector,
   output reg	    writeStrobe
);

// states of encoder state machine
reg [3:0] state; 
localparam STATE_SYN0 = 4'd0;      // 56 bytes sync pattern (0xff) 
localparam STATE_ADDR = 4'd1;      // 10 bytes address block
localparam STATE_SYN1 = 4'd2;      // 5 bytes sync pattern (0xff) 
localparam STATE_DHDR = 4'd3;      // 4 bytes data block header
localparam STATE_DZRO = 4'd4;      // 8 encoded zero bytes in data block
localparam STATE_DPRE = 4'd5;      // 4 bytes data prefetch
localparam STATE_DATA = 4'd6;      // the payload itself
localparam STATE_DSUM = 4'd7;      // 4 bytes data checksum
localparam STATE_DTRL = 4'd8;      // 3 bytes data block trailer
localparam STATE_WAIT = 4'd15;     // wait until start of next sector

// count bytes per sector
reg [9:0] count;
reg [3:0] sector;
reg [8:0] src_offset;

// address to request byte from track buffer
assign addr = { sector, src_offset };   
   
// parts of an address block
wire [5:0] sec_in_tr = {2'b00, sector};
wire [5:0] track_low = track[5:0];
wire [5:0] track_hi = { side, 4'b0000, track[6] };
wire [5:0] format = { sides, 5'h2 };          // double sided = 22, single sided = 2
wire [5:0] checksum = track_low ^ sec_in_tr ^ track_hi ^ format;

// data input to the sony encoder during address block
wire [5:0] sony_addr_in =
	      (count == 3)?track_low:
	      (count == 4)?sec_in_tr:
	      (count == 5)?track_hi:
	      (count == 6)?format:
	      checksum;

// data input to the sony encoder during data header
wire [5:0] sony_dhdr_in = sec_in_tr;
	      
wire [5:0] sony_dsum_in =
	      (count == 0)?{ c3[7:6], c2[7:6], c1[7:6] }:
	      (count == 1)?c3[5:0]:
	      (count == 2)?c2[5:0]:
	      c1[5:0];
   
// feed data into sony encoder
wire [5:0] si = 
	      (state == STATE_ADDR)?sony_addr_in:
	      (state == STATE_DHDR)?sony_dhdr_in:
	      (state == STATE_DZRO)?nib_out:
	      (state == STATE_DPRE)?nib_out:
	      (state == STATE_DATA)?nib_out:
	      (state == STATE_DSUM)?sony_dsum_in:
	      6'h3f;
   
// encoder table taken from MESS emulator
wire [7:0] sony_to_disk_byte =
	      (si==6'h00)?8'h96:(si==6'h01)?8'h97:(si==6'h02)?8'h9a:(si==6'h03)?8'h9b: // 0x00
	      (si==6'h04)?8'h9d:(si==6'h05)?8'h9e:(si==6'h06)?8'h9f:(si==6'h07)?8'ha6:
	      (si==6'h08)?8'ha7:(si==6'h09)?8'hab:(si==6'h0a)?8'hac:(si==6'h0b)?8'had:
	      (si==6'h0c)?8'hae:(si==6'h0d)?8'haf:(si==6'h0e)?8'hb2:(si==6'h0f)?8'hb3:
	      
	      (si==6'h10)?8'hb4:(si==6'h11)?8'hb5:(si==6'h12)?8'hb6:(si==6'h13)?8'hb7: // 0x10
	      (si==6'h14)?8'hb9:(si==6'h15)?8'hba:(si==6'h16)?8'hbb:(si==6'h17)?8'hbc:
	      (si==6'h18)?8'hbd:(si==6'h19)?8'hbe:(si==6'h1a)?8'hbf:(si==6'h1b)?8'hcb:
	      (si==6'h1c)?8'hcd:(si==6'h1d)?8'hce:(si==6'h1e)?8'hcf:(si==6'h1f)?8'hd3:

	      (si==6'h20)?8'hd6:(si==6'h21)?8'hd7:(si==6'h22)?8'hd9:(si==6'h23)?8'hda: // 0x20
	      (si==6'h24)?8'hdb:(si==6'h25)?8'hdc:(si==6'h26)?8'hdd:(si==6'h27)?8'hde:
	      (si==6'h28)?8'hdf:(si==6'h29)?8'he5:(si==6'h2a)?8'he6:(si==6'h2b)?8'he7:
	      (si==6'h2c)?8'he9:(si==6'h2d)?8'hea:(si==6'h2e)?8'heb:(si==6'h2f)?8'hec:
	      
	      (si==6'h30)?8'hed:(si==6'h31)?8'hee:(si==6'h32)?8'hef:(si==6'h33)?8'hf2: // 0x30
	      (si==6'h34)?8'hf3:(si==6'h35)?8'hf4:(si==6'h36)?8'hf5:(si==6'h37)?8'hf6:
	      (si==6'h38)?8'hf7:(si==6'h39)?8'hf9:(si==6'h3a)?8'hfa:(si==6'h3b)?8'hfb:
	      (si==6'h3c)?8'hfc:(si==6'h3d)?8'hfd:(si==6'h3e)?8'hfe:            8'hff;
	      
// output data during address block
wire [7:0] odata_addr =
	      (count == 0)?8'hd5:
	      (count == 1)?8'haa:
	      (count == 2)?8'h96:
	      (count == 8)?8'hde:
	      (count == 9)?8'haa:
	      sony_to_disk_byte;
   
wire [7:0] odata_dhdr =
	      (count == 0)?8'hd5:
	      (count == 1)?8'haa:
	      (count == 2)?8'had:
	      sony_to_disk_byte;
  
wire [7:0] odata_dtrl =
	      (count == 0)?8'hde:
	      (count == 1)?8'haa:
	      8'hff;
   	      
// demultiplex output data
assign odata = (state == STATE_ADDR)?odata_addr:
	       (state == STATE_DHDR)?odata_dhdr:
	       (state == STATE_DZRO)?sony_to_disk_byte:
	       (state == STATE_DPRE)?sony_to_disk_byte:
	       (state == STATE_DATA)?sony_to_disk_byte:
	       (state == STATE_DSUM)?sony_to_disk_byte:
	       (state == STATE_DTRL)?odata_dtrl:
	       8'hff;
   
// ------------------------ nibbler ----------------------------

reg [7:0]  c1;
reg [7:0]  c2;
reg 	   c2x;
reg [7:0]  c3;
reg        c3x;

wire       nibbler_reset = (state == STATE_DHDR);
reg [1:0]  cnt;

reg [7:0] nib_xor_0;
reg [7:0] nib_xor_1;
reg [7:0] nib_xor_2;

// request an input byte. this happens 4 byte ahead of output.
// only three bytes are read while four bytes are written due
// to 6:2 encoding
wire strobe = ((state == STATE_DPRE) || 
	       ((state == STATE_DATA) && (count < 683-4-1))) 
     && (cnt != 3);

reg [7:0] data_latch;
always @(posedge clk) if(ready && strobe) data_latch <= data;

always @(posedge clk or posedge nibbler_reset) begin
   if(nibbler_reset) begin
      c1 <= 8'h00;
      c2 <= 8'h00;
      c2x <= 1'b0;
      c3 <= 8'h00;
      c3x <= 1'b0;
      cnt <= 2'd0;
      nib_xor_0 <= 8'h00;
      nib_xor_1 <= 8'h00;
      nib_xor_2 <= 8'h00;
   end else if(ready && ((state == STATE_DPRE) || (state == STATE_DATA))) begin
      cnt <= cnt + 2'd1;
      
      // memory read during cnt 0-3
      if(count < 683-4) begin
	 
	 // encode first byte
	 if(cnt == 1) begin
	    c1 <= { c1[6:0], c1[7] };
	    { c3x, c3 } <= { 1'b0, c3 } + { 1'b0, nib_in } + { 8'd0, c1[7] };
	    nib_xor_0 <= nib_in ^ { c1[6:0], c1[7] };
	 end
	 
	 // encode second byte
	 if(cnt == 2) begin
	    { c2x, c2 } <= { 1'b0, c2 } + { 1'b0, nib_in } + { 8'd0, c3x };
	    c3x <= 1'b0;
	    nib_xor_1 <= nib_in ^ c3;
	 end
	 
	 // encode third byte
	 if(cnt == 3) begin
	    c1 <= c1 + nib_in + { 7'd0, c2x };
	    c2x <= 1'b0;
	    nib_xor_2 <= nib_in ^ c2;
	 end
      end else begin
	 // since there are 512/3 = 170 2/3 three byte blocks in a sector the
	 // last run has to be filled up with zeros
	 if(cnt == 3)
	   nib_xor_2 <= 8'h00;
      end
   end
end
   
// bytes going into the nibbler
wire [7:0] nib_in = (state == STATE_DZRO)?8'h00:data_latch;
		
// four six bit units come out of the nibbler
wire [5:0] nib_out =
	   (cnt == 1)?nib_xor_0[5:0]:
	   (cnt == 2)?nib_xor_1[5:0]:
	   (cnt == 3)?nib_xor_2[5:0]:
	   { nib_xor_0[7:6], nib_xor_1[7:6], nib_xor_2[7:6] };
   
always @(posedge clk or posedge rst) begin
   if(rst) begin
      count <= 10'd0;
      state <= STATE_SYN0;
      sector <= 4'd0;
      src_offset <= 9'd0;
   end else if(ready) begin
      count <= count + 10'd1;
      
      if(strobe)
	src_offset <= src_offset + 9'd1;
      
      case(state)
	
	// send 14*4=56 sync bytes
	STATE_SYN0: begin
	   if(count == 55-12) begin
	      state <= STATE_ADDR;
	      count <= 10'd0;
	   end
	end
	
	// send 10 bytes address block
	STATE_ADDR: begin
	   if(count == 9) begin
	      state <= STATE_SYN1;
	      count <= 10'd0;
	   end
	end
	
	// send 5 sync bytes
	STATE_SYN1: begin
	   if(count == 4+12) begin
	      state <= STATE_DHDR;
	      count <= 10'd0;
	   end
	end
	
   	// send 4 bytes data block hdr
	STATE_DHDR: begin
	   if(count == 3) begin
	      state <= STATE_DZRO;
	      count <= 10'd0;
	   end
	end
	
      	// send 12 zero bytes before data block
	STATE_DZRO: begin
	   if(count == 11) begin
	      state <= STATE_DPRE;
	      count <= 10'd0;
	   end
	end
	
       	// start prefetching 4 bytes data
	STATE_DPRE: begin
	   if(count == 3) begin
	      state <= STATE_DATA;
	      count <= 10'd0;
	   end
	end
	
      	// send 512 bytes data block 6:2 encoded in 683 bytes
	STATE_DATA: begin
	   if(count == 682) begin
	      state <= STATE_DSUM;
	      count <= 10'd0;
	   end
	end
	
       	// send 4 bytes data checksum
	STATE_DSUM: begin
	   if(count == 3) begin
	      state <= STATE_DTRL;
	      count <= 10'd0;
	   end
	end
	
       	// send 3 bytes data block trailer
	STATE_DTRL: begin
	   if(count == 2) begin
	      state <= STATE_WAIT;
	      count <= 10'd0;
	   end
	end
	
	// fill sector up to 1024 bytes
	STATE_WAIT: begin
	   count <= 10'd0;
	   state <= STATE_SYN0;
	   src_offset <= 9'd0;
	   
	   // interleave of 2
	   if((sector == spt-4'd2) || (sector == spt-4'd1))
	     sector <= { 3'd0, !sector[0] }; 
	   else
	     sector <= sector + 4'd2;
	end
      endcase
   end 
end

// disk byte in
wire [7:0] dbi = writeData;   
   
// disk_byte_to_sony (gcr)
wire [6:0] disk_byte_to_sony =
	   // 0x00-0x0f
	   (dbi == 8'h96)?7'h00:(dbi == 8'h97)?7'h01:(dbi == 8'h9a)?7'h02:(dbi == 8'h9b)?7'h03:
	   (dbi == 8'h9d)?7'h04:(dbi == 8'h9e)?7'h05:(dbi == 8'h9f)?7'h06:(dbi == 8'ha6)?7'h07:
	   (dbi == 8'ha7)?7'h08:(dbi == 8'hab)?7'h09:(dbi == 8'hac)?7'h0a:(dbi == 8'had)?7'h0b:
	   (dbi == 8'hae)?7'h0c:(dbi == 8'haf)?7'h0d:(dbi == 8'hb2)?7'h0e:(dbi == 8'hb3)?7'h0f:
	   // 0x10-0x1f
	   (dbi == 8'hb4)?7'h10:(dbi == 8'hb5)?7'h11:(dbi == 8'hb6)?7'h12:(dbi == 8'hb7)?7'h13:
	   (dbi == 8'hb9)?7'h14:(dbi == 8'hba)?7'h15:(dbi == 8'hbb)?7'h16:(dbi == 8'hbc)?7'h17:
	   (dbi == 8'hbd)?7'h18:(dbi == 8'hbe)?7'h19:(dbi == 8'hbf)?7'h1a:(dbi == 8'hcb)?7'h1b:
	   (dbi == 8'hcd)?7'h1c:(dbi == 8'hce)?7'h1d:(dbi == 8'hcf)?7'h1e:(dbi == 8'hd3)?7'h1f:
	   // 0x20-0x2f
	   (dbi == 8'hd6)?7'h20:(dbi == 8'hd7)?7'h21:(dbi == 8'hd9)?7'h22:(dbi == 8'hda)?7'h23:
	   (dbi == 8'hdb)?7'h24:(dbi == 8'hdc)?7'h25:(dbi == 8'hdd)?7'h26:(dbi == 8'hde)?7'h27:
	   (dbi == 8'hdf)?7'h28:(dbi == 8'he5)?7'h29:(dbi == 8'he6)?7'h2a:(dbi == 8'he7)?7'h2b:
	   (dbi == 8'he9)?7'h2c:(dbi == 8'hea)?7'h2d:(dbi == 8'heb)?7'h2e:(dbi == 8'hec)?7'h2f:
	   // 0x30-0x3f
	   (dbi == 8'hed)?7'h30:(dbi == 8'hee)?7'h31:(dbi == 8'hef)?7'h32:(dbi == 8'hf2)?7'h33:
	   (dbi == 8'hf3)?7'h34:(dbi == 8'hf4)?7'h35:(dbi == 8'hf5)?7'h36:(dbi == 8'hf6)?7'h37:
	   (dbi == 8'hf7)?7'h38:(dbi == 8'hf9)?7'h39:(dbi == 8'hfa)?7'h3a:(dbi == 8'hfb)?7'h3b:
	   (dbi == 8'hfc)?7'h3c:(dbi == 8'hfd)?7'h3d:(dbi == 8'hfe)?7'h3e:(dbi == 8'hff)?7'h3f:
	   
	   (dbi == 8'haa)?7'h40:(dbi == 8'hd5)?7'h41:   // "special" bytes
	   
	   7'h7f;                                       // not a valid gcr byte -> error
   

// data out of the decoder
reg [1:0] writePhase;

reg [3:0] writeState;
localparam WRITE_STATE_IDLE   = 4'd0;
localparam WRITE_STATE_PRE    = 4'd1;
localparam WRITE_STATE_DATA   = 4'd2;
localparam WRITE_STATE_CSUM   = 4'd3;
localparam WRITE_STATE_TRAIL  = 4'd4;
localparam WRITE_STATE_FAIL   = 4'd5;
localparam WRITE_STATE_OK     = 4'd6;   

// parse incoming bytes written MacOS into IWM
always @(posedge clk) begin
   reg [7:0] c2w, c1w, c0w;
   
   if (rst) begin		
      writeAddr <= 9'd0;
      writePhase <= 2'd0;
      writeState <= WRITE_STATE_IDLE;
      writeStrobe <= 1'b0;
      error <= 1'b0;
   end else if(en) begin
      reg writeDataStrobeD;
      reg [5:0] upper;
      reg	carry;		      
      
      writeDataStrobeD <= writeDataStrobe;      
      if(writeDataStrobe ^ writeDataStrobeD) begin
      
	 // parse bytes to be written
	 case(writeState)
	   
	   // skip/parse sector header d5/aa/ad/<sit>
	   WRITE_STATE_IDLE: begin
	      // In write phase 0 to 2 check for d5/aa/ad. In write phase 3 the
	      // encoded sector number is being transferred.
	      
	      writePhase <= writePhase + 2'd1;		      
	      if((writePhase == 2'd0 && dbi != 8'hd5) || 
		 (writePhase == 2'd1 && dbi != 8'haa) ||
		 (writePhase == 2'd2 && dbi != 8'had)) writePhase <= 2'd0;
	      else if(writePhase == 2'd3) begin
		 /* receive sector number */

		 // Check if this is actually the sector under the virtual head
		 // Otherwise this would overwrite the wrong sector.
		 if(disk_byte_to_sony[3:0] != sector)
		   writeState <= WRITE_STATE_FAIL;
		 else begin		 
		    writeSector <= disk_byte_to_sony[3:0];
		 
		    writeState <= WRITE_STATE_PRE;
		    writeAddr <= 9'd0;
		    writePhase <= 2'd0;
		 
		    // reset the decoder sum/counter
		    c2w <= 8'h00;
		    c1w <= 8'h00;
		    c0w <= 8'h00;
		 end
	      end
	   end // case: WRITE_STATE_IDLE
	   
	   /* (preamble) data decoding */
	   WRITE_STATE_PRE,WRITE_STATE_DATA: begin
	      logic [7:0] val = 8'h00;	      
	      
	      case(writePhase)
		2'd0: begin
		   // first of four gcr encoded 6 bit nibbles
		   // contains the upper bits of the follwing three nibbles
		   upper <= disk_byte_to_sony[5:0];
		   { carry, c2w } <= { c2w[7:0], c2w[7] };
		end
		
		2'd1: begin
		   val = { upper[5:4], disk_byte_to_sony[5:0] } ^ c2w;			   
		   { carry, c0w } <= {1'b0, c0w} + {1'b0, val} + { 8'h00, carry};
		end
		
		2'd2: begin
		   val = { upper[3:2], disk_byte_to_sony[5:0] } ^ c0w;
		   { carry, c1w } <= {1'b0, c1w} + {1'b0, val} + { 8'h00, carry};
		end
		
		2'd3: begin
		   val = { upper[1:0], disk_byte_to_sony[5:0] } ^ c1w;
		   // don't generate carry as it's not evaluated in phase 0		   
		   if(writeAddr != 9'd511) c2w <= c2w + val + { 7'h00, carry};
		end	
	      endcase		      

	      // output data into buffer
	      if(writePhase) begin
		 writeDataDecoded <= val;
		 writeAddr <= writeAddr + 9'd1;
		 if(writeState == WRITE_STATE_DATA && writeAddr != 9'd511)
		   writeStrobe <= !writeStrobe;
	      end
	      
	      // skip the first 12 leading bytes (first counter run starts at 1)
	      if(writeState == WRITE_STATE_PRE && writeAddr == 9'd12 && writePhase) begin
		 writeState <= WRITE_STATE_DATA;
		 writeAddr <= 9'd0;
		 writeStrobe <= !writeStrobe;  // strobe the first data byte
	      end
	      
	      // leave data payload state after one complete sector 
	      if(writeState == WRITE_STATE_DATA && writeAddr == 9'd511 && writePhase) begin
		 writeState <= WRITE_STATE_CSUM;
		 writeAddr <= 9'd0;

		 // current disk byte is the upper bits of the checksum
		 upper <= disk_byte_to_sony[5:0];
	      end
	      
	      // check if gcr decoder error flag has been raised		      
	      if(disk_byte_to_sony[6]) writeState <= WRITE_STATE_FAIL;
	      
	      writePhase <= writePhase + 2'd1;
	   end // case: WRITE_STATE_PRE,WRITE_STATE_DATA

	   /* checksum verification. We could actually skip this. If this fails then */
	   WRITE_STATE_CSUM: begin
	      writePhase <= writePhase + 2'd1;

	      case(writePhase)
		2'd0: begin
		   logic [7:0] c0x = { upper[5:4], disk_byte_to_sony[5:0] };
		   
		   // verify c0w, go into error state on failure
		   if({ upper[5:4], disk_byte_to_sony[5:0] } != c0w) writeState <= WRITE_STATE_FAIL;
		end
		2'd1: begin
		   logic [7:0] c1x = { upper[3:2], disk_byte_to_sony[5:0] };
		   
		   // verify c1w, go into error state on failure
		   if({ upper[3:2], disk_byte_to_sony[5:0] } != c1w) writeState <= WRITE_STATE_FAIL;
		end
		2'd2: begin
		   logic [7:0] c2x = { upper[1:0], disk_byte_to_sony[5:0] };
		   
		   // verify c2w, go into error state on failure
		   if({ upper[1:0], disk_byte_to_sony[5:0] } != c2w) writeState <= WRITE_STATE_FAIL;
		   else begin
		      writeState <= WRITE_STATE_TRAIL;  // if we get here, then the sector data is fine
		      writePhase <= 2'd0;
		   end
		end
	      endcase // case (writePhase)
	      
	      // check if gcr decoder error flag has been raised		      
	      if(disk_byte_to_sony[6]) writeState <= WRITE_STATE_FAIL;		      
	   end // case: WRITE_STATE_CSUM
	   
	   WRITE_STATE_TRAIL: begin
	      // sector received successfully, check for final DE/AA
	      if(writePhase == 2'd0 && writeData != 8'hde) 
		writeState <= WRITE_STATE_FAIL;  // no de, enter error state
	      
	      if(writePhase == 2'd1) begin
		 if(writeData != 8'haa) writeState <=  WRITE_STATE_FAIL;  // no aa, enter error state
		 else                   writeState <=  WRITE_STATE_OK;    // otherwise all fine!
	      end
	      
	      writePhase <= writePhase + 2'd1;
	   end // case: WRITE_STATE_TRAIL
	   
	   WRITE_STATE_OK: begin
	      // sector received correctly
	      // ...
	      
	      // and wait for next sector write attempt
	      writeState <= WRITE_STATE_IDLE;
	   end
	   
	   WRITE_STATE_FAIL: begin
	      // handle error state ...
	      
	      error <= 1'b1;
	      // and wait for next sector write attempt
	      writeState <= WRITE_STATE_IDLE;
	   end
	 endcase
      end
   end
end

endmodule
