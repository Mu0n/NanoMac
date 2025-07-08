/*
  keyboard.v
 
  a generic keyboard implementation for the PlusToo 
*/

module keyboard (
    input	     clk,
    input	     en,
    input	     reset,

    input	     kbd_strobe,
    input [9:0]	     kbd_data,
		 
    // Mac Plus
    input [7:0]	     data_out,
    input	     strobe_out,
    output [7:0]     data_in,
    output	     strobe_in
);

reg [9:0]  keymac;
reg	   key_pending;
reg [19:0] pacetimer;
reg	   inquiry_active;
reg	   got_key;
wire	   tick_short;
wire	   tick_long;
wire	   pop_key;
   
reg	   cmd_inquiry;
reg	   cmd_instant;
reg	   cmd_model;
reg	   cmd_test;
   
/* --- Mac side --- */

/* Latch commands from Mac */
always@(posedge clk or posedge reset) begin
  if (reset) begin
     cmd_inquiry <= 0;
     cmd_instant <= 0;
     cmd_model <= 0;
     cmd_test <= 0;
  end else if (en) begin
     if (strobe_out) begin
	cmd_inquiry <= 0;
	cmd_instant <= 0;
	cmd_model <= 0;
	cmd_test <= 0;
	case(data_out)
	  8'h10: cmd_inquiry <= 1;
	  8'h14: cmd_instant <= 1;
	  8'h16: cmd_model   <= 1;
	  8'h36: cmd_test    <= 1;
	endcase
     end
  end
end
   
/* Divide our clock to pace our responses to the Mac. tick_short ticks
 * when we can respond to a command, and tick_long ticks when an inquiry
 * command shall timeout
 */
always@(posedge clk or posedge reset) begin
   if (reset)
     pacetimer <= 0;
   else if (en) begin
      /* reset counter on command from Mac */
      if (strobe_out)
	pacetimer <= 0;		  
      else if (!tick_long)
	pacetimer <= pacetimer + 1'd1;
   end
end
   
assign tick_long  = pacetimer == 20'hfffff;
assign tick_short = pacetimer == 20'h00fff;
   
/* Delay inquiry responses to after tick_short */
always@(posedge clk or posedge reset) begin
   if (reset)
     inquiry_active <= 0;
   else if (en) begin
      if (strobe_out | strobe_in)
	inquiry_active <= 0;
      else if (tick_short)
	inquiry_active <= cmd_inquiry;		  
   end	
end
   
/* Key answer to the mac */
assign pop_key = (cmd_instant & tick_short) |
		 (inquiry_active & tick_long) |
		 (inquiry_active & key_pending);
   
/* Reply to Mac */
assign strobe_in = ((cmd_model | cmd_test) & tick_short) | pop_key;	
   
/* Handle key_pending, and multi-byte keypad responses */
reg keypad_byte2;
reg keypad_byte3;
always @(posedge clk or posedge reset) begin
   if (reset) begin
      key_pending <= 0;
      keypad_byte2 <= 0;
      keypad_byte3 <= 0;
   end else if (en) begin
      if (cmd_model | cmd_test)
	key_pending <= 0;
      else if (pop_key) begin
	 if(key_pending & keymac[9] && !keypad_byte3) begin
	    keypad_byte3 <= 1;
	 end else if (key_pending & keymac[8] & !keypad_byte2) begin
	    keypad_byte2 <= 1;
	 end else begin
	    key_pending <= 0;
	    keypad_byte2 <= 0;
	    keypad_byte3 <= 0;
	   end
      end else if (!key_pending & got_key)
	key_pending <= 1;
   end
end

/* incoming data is valid on the changing edge of strobe */   
reg caps = 1'b0;
always @(posedge clk) begin
   reg strobe;
      
   if(en) begin
      got_key <= 1'b0;	 
      if(kbd_strobe != strobe) begin

	 // caps lock needs some special treatment as the mac expects
	 // a single up or down event per full key stroke. Basically as
	 // if the key was a physical toggle switch

	 // totally ignore the incoming caps release event
	 if(kbd_data != 10'hf3) begin
	    // caps press event
	    if(kbd_data == 10'h73) begin
	       keymac <= { kbd_data[9:8], caps, kbd_data[6:0] };
	       caps <= !caps;	       
	    end else
	      keymac <= kbd_data;
	    
	    got_key <= 1'b1;
	 end
      end
      
      strobe <= kbd_strobe;	 
   end
end
   
/* Data to Mac */
assign data_in = cmd_test    ? 8'h7d :
		 cmd_model   ? 8'h0b :
		 key_pending ? (keymac[9] & !keypad_byte3 ? {keymac[7],7'h71} :
			      ((keymac[8] & !keypad_byte2) ? 8'h79 : keymac[7:0])) :
		 8'h7b;	

endmodule
