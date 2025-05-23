// generates 1024x768 (actually 512x768) @ 60Hz, from a 32.5MHz input clock
module videoTimer(
	input clk,
	input clk8_en_n,
	input clk8_en_p,
	input videoCycle,
	input vid_alt,
	output [20:0] videoAddr,	 
	output reg hsync,
	output reg vsync,
	output _hblank,
	output _vblank,
	output loadPixels,
	output refresh
);

	// timing data from http://tinyvga.com/vga-timing/1024x768@60Hz
   // horizontal timing is doubled due to video clock being 32Mhz
	localparam 	kTotalWidth = 704,
			kVisibleWidth = 512,
			kHsyncStart = 526,
			kHsyncEnd = 529,
			kTotalHeight = 370,
			kVisibleHeight = 342,
			kVsyncStart = 342,
			kVsyncEnd = 346;


	reg [9:0] xpos; // 0 ... 703
	reg [8:0] ypos; // 0 ... 369

	wire endline = (xpos == kTotalWidth-1);

        // reserve one video cycle per scan line for refresh
        assign refresh = (xpos[9:3] == 7'h54);
   
	always @(posedge clk) begin
		if (clk8_en_n || clk8_en_p) begin
			if (endline)
				xpos <= 0;
			else if (xpos == 0 && !videoCycle)
				// hold xpos at 0, until xpos and videoCycle are in phase
				xpos <= 0;
			else
				xpos <= xpos + 1'b1;
		   
			if (endline) begin
				if (ypos == kTotalHeight-1)
					ypos <= 0;
				else
					ypos <= ypos + 1'b1;	
			end
		   
			hsync <= ~(xpos >= kHsyncStart && xpos <= kHsyncEnd);  
			vsync <= ~(ypos >= kVsyncStart && ypos <= kVsyncEnd);
		end
	end

	assign _hblank = ~(xpos >= kVisibleWidth);
	assign _vblank = ~(ypos >= kVisibleHeight);
	
	assign videoAddr = 21'h1FD380 - (vid_alt ? 16'h0 : 16'h4000) + { ypos[8:0], xpos[8:4] };	
	assign loadPixels = _vblank && xpos < kVisibleWidth && videoCycle & !xpos[3];
	
endmodule
