module videoShifter(
    input	 clk,
    input	 clk8_en_n,
    input	 clk8_en_p,
    input [15:0] dataIn,
    input	 loadPixels,
    output	 pixelOut
);
	
// a 0 bit is white, and a 1 bit is black
// data is shifted out MSB first
reg [15:0] shiftRegister = 16'hffff;  // prevent white screen during reset
assign pixelOut = ~shiftRegister[15];
   
// the video shifter runs at 16 Mhz and is being run on both 8Mhz edges
// load new data after the end of each video cycle
always @(posedge clk) begin
  if(clk8_en_n || clk8_en_p) begin
     if(loadPixels)
       shiftRegister <= dataIn; // 16'h8000;
     else
       shiftRegister <= { shiftRegister[14:0], 1'b1 };   
  end
end
    
//    shiftRegister <= (loadPixels && clk8_en_p)?/*dataIn*/16'h8000:{ shiftRegister[14:0], 1'b1 };
   
endmodule
