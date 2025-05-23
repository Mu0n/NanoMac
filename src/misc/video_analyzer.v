//
// video_analyzer.v
//
// try to derive video parameters from hs/vs
//

module video_analyzer 
(
 // system interface
 input		  clk,
 input		  hs,
 input		  vs,

 output reg	  vreset
);
   

// generate a reset signal in the upper left corner of active video used
// to synchonize the HDMI video generation to the Atari ST
reg vsD, hsD;
reg [11:0] hcnt;
reg [11:0] hcntL;
reg [9:0] vcnt;
reg [9:0] vcntL;
reg changed;

always @(posedge clk) begin
    // ---- hsync processing -----
    hsD <= hs;

    // begin of hsync, falling edge
    if(!hs && hsD) begin
        // check if line length has changed during last cycle
        hcntL <= hcnt;
        if(hcntL != hcnt)
            changed <= 1'b1;

        hcnt <= 0;
    end else
        hcnt <= hcnt + 13'd1;

    if(!hs && hsD) begin
       // ---- vsync processing -----
       vsD <= vs;
       // begin of vsync, falling edge
       if(!vs && vsD) begin
          // check if image height has changed during last cycle
          vcntL <= vcnt;
          if(vcntL != vcnt)
             changed <= 1'b1;

          vcnt <= 0;	  
       end else
         vcnt <= vcnt + 10'd1;
    end

   // the reset signal is sent to the HDMI generator. On reset the
   // HDMI re-adjusts its counters to the start of the visible screen
   // area
   
   vreset <= 1'b0;
   // account for back porches to adjust image position within the
   // HDMI frame. Values for HDMI test: (hcnt == 99) && (vcnt == 8)
	 
   if( (hcnt == 181) && (vcnt == 27) && changed) begin
      vreset <= 1'b1;
      changed <= 1'b0;
   end
end


endmodule
