/* 
  floppy_track_buffer.v
 
  Read floppy tracks from floppy disk images stored on sd card
 */

module floppy_track_buffer 
   (
    input	      clk,
    input	      rst,

    // iwm/floppy info of currently addressed track
    input [1:0]	      eject,
    input	      drive, // 0=int, 1=ext
    input	      side,
    input [6:0]	      track, // current track
    output [3:0]      spt,

    // floppy interface to access data in buffer
    output	      ready, // valid track is in buffer
    input [13:0]      addr, // byte requested
    output reg [7:0]  data, // data returned

    // data written by IWM and decoded into sector format
    input [7:0]	      writeDataDecoded,
    input [8:0]	      writeAddr,
    input [3:0]	      writeSector,
    input	      writeStrobe,

    // a floppy disk image may at most be 819200 bytes or 1600 sectors big
    input [31:0]      sd_img_size,
    input [1:0]	      sd_img_mounted,
    output [1:0]      inserted,
    output [1:0]      sides,

    output reg [10:0] sd_lba,
    output reg [1:0]  sd_rd,
    output reg [1:0]  sd_wr,
    input	      sd_busy,
    input	      sd_done,
    input [8:0]	      sd_addr,
    input	      sd_data_en,
    input [7:0]	      sd_data_in,
    output reg [7:0]  sd_data_out
);

reg [31:0] size [2] = {0,0};   
assign inserted = { size[1] != 32'd0, size[0] != 32'd0 };   

// Proper sides handling is actually not needed since the images contain the
// tracks for both sides subsequently and it doesn't make a difference if
// e.g. the 5th track of a single sided disk is read or the third track of
// the second side of a double sided disk. Both are at the same offset
// within the image file. We handle sides here, anyway, as it's just cleaner.
assign sides = { size[1] > 32'd409600, size[0] > 32'd409600};   
   
always @(posedge clk) begin
   if(sd_img_mounted[0])
     size[0] <= sd_img_size;
   else if(eject[0])
     size[0] <= 32'd0;
      
   if(sd_img_mounted[1])
     size[1] <= sd_img_size;
   else if(eject[1])
     size[1] <= 32'd0;
end   
   
// ---------------- calculate side/track into offset into floppy image ---------------

// number of sectors on current track
assign spt =
     (track[6:4] == 3'd0)?4'd12: // track  0 - 15
     (track[6:4] == 3'd1)?4'd11: // track 16 - 31
     (track[6:4] == 3'd2)?4'd10: // track 32 - 47
     (track[6:4] == 3'd3)?4'd9:  // track 48 - 63
     4'd8;                       // track 64 - ...

// The track to be used for Sd card IO depends on read or write. On read
// it's the newly requested track, on write it's the one in the buffer.
wire [6:0] iotrack;
   
// all possible tack*sector factors
wire [9:0] track_times_12 =      // x*12 = x*8 + x*4
    { iotrack, 3'b000 } +        // x<<3 +
    { 1'b0, iotrack, 2'b00 };    // x<<2 
   
wire [9:0] track_times_11 =      // x*11 = x*8 + x*2 + x*1
    { iotrack, 3'b000 } +        // x<<3 +
    { 2'b00, iotrack, 1'b0 } +   // x<<1 +
    { 3'b000, iotrack };         // x<<0 

wire [9:0] track_times_10 =      // x*10 = x*8 + x*2
    { iotrack, 3'b000 } +        // x<<3 +
    { 2'b00, iotrack, 1'b0 };    // x<<1

wire [9:0] track_times_9 =       // x*9 = x*8 + x*1
    { iotrack, 3'b000 } +        // x<<3 +
    { 3'b000, iotrack };         // x<<0

wire [9:0] track_times_8 =       // x*8
    { iotrack, 3'b000 };         // x<<3
   
// sector offset of current track is the sum of all sectors on all tracks before
wire [6:0] trackm1 = iotrack - 7'd1;
wire [9:0] soff =
      (iotrack == 0)?10'd0:                                               // track  0
      (trackm1[6:4] == 3'd0)?track_times_12:                              // track  1 - 16
      (trackm1[6:4] == 3'd1)?(track_times_11 + 10'd16):                   // track 17 - 32 
      (trackm1[6:4] == 3'd2)?(track_times_10 + 10'd32 + 10'd16):          // track 33 - 48 
      (trackm1[6:4] == 3'd3)?(track_times_9 + 10'd48 + 10'd32 + 10'd16):  // track 49 - 64 
      (track_times_8 + 10'd64 + 10'd48 + 10'd32 + 10'd16);                // track 65 -
   
// This encoder contains a buffer for one single track which it will refill
// from SD card whenever needed.

reg [8:0]  track_in_buffer;         // track currently stored in buffer (drive/side/track)
reg [7:0]  track_buffer [12*512];   // max 12 sectors per track and side
reg [11:0] track_buffer_dirty;      // sectors have been written
reg [3:0]  track_loader_sector;     // sector 0..11 within track currently being read
reg [7:0]  track_loader_state;
reg [8:0]  track_in_progress;
reg [3:0]  track_spt;   

// iowriting indicates that the track in buffer is valid and IWM writes would go to that buffer
wire iowriting = (track_loader_state == 0) && ready;  
assign iotrack = iowriting?track_in_buffer[6:0]:track; // current track
   
// determine which sector to write next
wire [3:0] track_sector_to_write =
	   track_buffer_dirty[0]?4'd0:
	   track_buffer_dirty[1]?4'd1:
	   track_buffer_dirty[2]?4'd2:
	   track_buffer_dirty[3]?4'd3:
	   track_buffer_dirty[4]?4'd4:
	   track_buffer_dirty[5]?4'd5:
	   track_buffer_dirty[6]?4'd6:	   
	   track_buffer_dirty[7]?4'd7:
	   track_buffer_dirty[8]?4'd8:
	   track_buffer_dirty[9]?4'd9:
	   track_buffer_dirty[10]?4'd10:
	   track_buffer_dirty[11]?4'd11:
	   4'd15;   
   
wire [8:0] track_requested = {drive, side, track};
assign ready = (track_in_buffer == track_requested);  
   
// read from internal track buffer
always @(posedge clk) begin
  if((track_loader_state == 4'd0) && ready)
    data <= track_buffer[addr];
  else
    sd_data_out <= track_buffer[{track_sector_to_write, sd_addr}];
end
      
// state machine to make sure the correct track is in buffer
always @(posedge clk) begin
   reg writeStrobeD;   
   
   if(rst) begin
      track_in_buffer <= 9'h1ff;      
      track_loader_state <= 8'd0;
      sd_rd <= 2'b00;
      sd_wr <= 2'b00;
      track_buffer_dirty <= 12'h000;      
   end else begin
      writeStrobeD <= writeStrobe;      
      
      case(track_loader_state)
	// idle state
	0: if(!ready && !sd_busy && inserted[drive]) begin

	   // flush dirty sectors before starting to read new
	   if(track_buffer_dirty) begin
	      // Take drive/side/track info from buffer as this is exactly
	      // what has changed to trigger the flush of the dirty buffer
	      
	      // twice the sector offset for double sided disk, soff is derived from
	      // track_in_buffer during write as well
	      sd_lba <= (sides[track_in_buffer[8]]?{soff,1'b0}:{1'b0,soff}) + 
 			(track_in_buffer[7]? { 6'd0, spt  }:11'd0) + // offset to other side
			{ 7'd0, track_sector_to_write };	     // write first dirty sector     
			
	      sd_wr <= track_in_buffer[8]?2'b10:2'b01;
	      track_loader_state <= 8'd5;

	   end else begin	   
	      track_in_buffer <= 9'h1ff;      // mark buffer contents invalid

	      // latch current track information as it may change during sd card access
	      track_in_progress <= track_requested;	   
	      track_spt <= spt;	   	   

	      // request first sector from sd card
	      track_loader_sector <= 4'd0;      
	      sd_lba <= (sides[drive]?{soff,1'b0}:{1'b0,soff}) + // twice the sector offset for double sided disk
 			(side? { 6'd0, spt  }:11'd0);            // offset to other side
	      sd_rd <= drive?2'b10:2'b01;

	      track_buffer_dirty <= 12'h000;      
	      track_loader_state <= 8'd1;
	   end
	end else if(ready && inserted[drive]) begin
	   // The track is valid and doesn't have to be reloaded. 
	   // Check if bytes are to be written by IWM

	   // TODO: Setting the dirty flag forces a writeback to sd card. The
	   // track codec can actually detect "write errors" which are basically
	   // malformed data being written to the IWM. In that case we may want
	   // to clear the dirty flag again, as we don't want the broken
	   // data to actually be written to sd card.	   
	   if( writeStrobe && !writeStrobeD ) begin
	      track_buffer_dirty[writeSector] <= 1'b1;	      
	      track_buffer[{writeSector, writeAddr}] <= writeDataDecoded;
	   end
	end

	// waiting for sd card to become busy
	1: if(sd_busy) begin
	   sd_rd <= 2'b00;	   
	   track_loader_state <= 8'd2;
	end
	   
	// sd card has read sector and is now returning sector data
	2: begin
	   if(sd_data_en) begin
	      track_buffer[{track_loader_sector, sd_addr}] <= sd_data_in;

	      // stop reading after byte 511	   
	      if(sd_addr == 9'd511)
		track_loader_state <= 8'd3;
	   end
	end

	// wait while busy is still set
	3: begin
	   if(!sd_busy)
	     track_loader_state <= 8'd4;
	end

	// received one sector, request next one
	4: begin
	   // check if we have all sectors for this track
	   if(track_loader_sector >= track_spt-1) begin
	      // yes, we did, mark track buffer as valid again
	      track_in_buffer <= track_in_progress;	      

	      // return to idle state
	      track_loader_state <= 8'd0;
	   end else begin	   
	      // check if track has changed
	      if(track_in_progress != track_requested) begin
		 // Requested track has changed. Abort,
		 // leave buffer marked invalid and allow
		 // loader to start allover
		 track_loader_state <= 8'd0;		 
	      end else begin
		 // The same track is still being requested,
		 // continue loading it
		 track_loader_sector <= track_loader_sector + 4'd1;      
		 sd_lba <= sd_lba + 11'd1;	      
		 sd_rd <= track_in_progress[8]?2'b10:2'b01;

		 // continue loading next sector
		 track_loader_state <= 8'd1;
	      end
	   end
	end

	// waiting for sd card to become busy
	5: if(sd_busy) begin
	   sd_wr <= 2'b00;	   
	   track_loader_state <= 8'd6;
	end

	// write one sector, return data and wait until not busy, anymore
	6: if(!sd_busy) begin
	   // buffer for this sector not dirty, anymore
	   track_buffer_dirty[track_sector_to_write] <= 1'b0;
	   track_loader_state <= 8'd0;
	end
      endcase      
   end
end   

endmodule
