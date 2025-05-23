module clocks (
	       input		clk,

	       output		clk8_en_p,
	       output		clk8_en_n,
	       output reg [2:0]	busPhase,

	       output		cycleReady,
	       output		videoBusControl,
	       output		cpuBusControl
	       );

`define CLK16  // run at 16Mhz master clock
   
reg busCycle;

`ifdef CLK16

always @(posedge clk) begin
   busPhase <= busPhase + 1'd1;
   if (busPhase == 3'd7)
     busCycle <= !busCycle;   
end

// caution: currently videoShifter requires cycleReady to be active during
// one of the clk8_en_X. This should be fixed ...
assign cycleReady =  busPhase == 3'd7;
assign clk8_en_p  =  busPhase[0];   
assign clk8_en_n  = !busPhase[0];

// video controls memory bus during the first cycle
assign videoBusControl = !busCycle;
// cpu controls memory bus during the second cycle
assign cpuBusControl = busCycle;   
`else	       
reg [1:0] busPhase;

always @(posedge clk) begin
   busPhase <= busPhase + 1'd1;
   if (busPhase == 2'b11)
     busCycle <= busCycle + 3'd1;
end
     
assign cycleReady = xyz;   
assign clk8_en_p  = busPhase == 2'd3;
assign clk8_en_n  = busPhase == 2'd1;

// video controls memory bus during the first cycle
assign videoBusControl = (busCycle == 3'b000);
// cpu controls memory bus during the second cycle
assign cpuBusControl = busCycle[1:0] == 2'b10;   
`endif

endmodule
