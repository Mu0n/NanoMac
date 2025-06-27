//
// video_analyzer.v
//
// try to derive video parameters from hs/vs
//

module video_analyzer 
(
 // system interface
 input	    clk,
 input	    hs,
 input	    vs,
 input	    wide,
 output reg vreset
);
   

// generate a reset signal in the upper left corner of active video used
// to synchonize the HDMI video generation to the Atari ST
reg vsD, hsD;
reg [11:0] hcnt;
reg [11:0] hcntL;
reg [9:0] vcnt;
reg [9:0] vcntL;
reg changed;
reg wideL;
   
always @(posedge clk) begin
    // ---- hsync processing -----
    hsD <= hs;

    // make sure changes in wide/normal also trigger
    // a vreset
    if(wide != wideL) begin
       changed <= 1'b1;
       wideL <= wide;
    end
   
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
   // HDMI frame.	 
   if( (hcnt == (wide?12'd117:12'd181)) && (vcnt == 10'd27) && changed) begin
      vreset <= 1'b1;
      changed <= 1'b0;
   end
end


endmodule
