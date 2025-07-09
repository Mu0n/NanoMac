/*
    hid.v
 
    hid (keyboard, mouse etc) interface to the IO MCU
  */

module hid (
  input		   clk,
  input		   reset,

  input		   data_in_strobe,
  input		   data_in_start,
  input [7:0]	   data_in,
  output reg [7:0] data_out,

  // input local db9 port events to be sent to MCU to e.g.
  // be able to control the OSD via joystick connected
  // to the FPGA
  input [5:0]	   db9_port, 
  output reg	   irq,
  input		   iack,

  // output HID data received from USB
  output [4:0]	   mouse,
  output reg	   kbd_strobe,
  output [9:0]     kbd_data,

  output reg [7:0] joystick0,
  output reg [7:0] joystick1
);

reg mouse_btn;
reg [1:0] mouse_x;
reg [1:0] mouse_y;

assign mouse = { ~mouse_btn, mouse_x, mouse_y };

reg [11:0] mouse_div;
reg [7:0] mouse_x_cnt;
reg [7:0] mouse_y_cnt;

reg [3:0] state;
reg [7:0] command;  
reg [7:0] device;   // used for joystick
   
reg irq_enable;
reg [5:0] db9_portD;
reg [5:0] db9_portD2;

reg	  kbd_trigger;   
reg [9:0] kbd_data_in;  

wire [8:0] macplus_keycode;   
keymap keymap (
 .code  ( kbd_data_in[6:0]  ),
 .mac   ( macplus_keycode )
);  

// 2 special modifier bits for extended key, 1 make/break bit and the code
assign kbd_data = { macplus_keycode[8:7], kbd_data_in[7], macplus_keycode[6:0] };   
	   
// process hid events
always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;
      mouse_div <= 12'd0;
      irq <= 1'b0;
      irq_enable <= 1'b0;
      kbd_strobe <= 1'b0;
      kbd_data_in <= 8'h00;      
   end else begin
      db9_portD <= db9_port;
      db9_portD2 <= db9_portD;

      if(kbd_trigger) begin
	 if(macplus_keycode != 9'h7f)
	   kbd_strobe <= !kbd_strobe;		 

	 kbd_trigger <= 1'b0;
      end
      
      // monitor db9 port for changes and raise interrupt
      if(irq_enable) begin
        if(db9_portD2 != db9_portD) begin
            // irq_enable prevents further interrupts until
            // the db9 state has actually been read by the MCU
            irq <= 1'b1;
            irq_enable <= 1'b0;
        end
      end

      if(iack) irq <= 1'b0;      // iack clears interrupt

      if(data_in_strobe) begin      
        if(data_in_start) begin
            state <= 4'd0;
            command <= data_in;
        end else begin
            if(state != 4'd15) state <= state + 4'd1;
	    
            // CMD 0: status data
            if(command == 8'd0) begin
                // return some dummy data for now ...
                if(state == 4'd0) data_out <= 8'h01;   // hid version 1
                if(state == 4'd1) data_out <= 8'h00;   // subversion 0
            end

            // CMD 1: keyboard data
            if(command == 8'd1) begin
                if(state == 4'd0) begin
                   kbd_data_in <= data_in;
		   kbd_trigger <= 1'b1;		   
		end
            end

            // CMD 2: mouse data
            if(command == 8'd2) begin
                if(state == 4'd0) mouse_btn <= data_in[0];
                if(state == 4'd1) mouse_x_cnt <= mouse_x_cnt + data_in;
                if(state == 4'd2) mouse_y_cnt <= mouse_y_cnt + data_in;
            end

            // CMD 3: receive digital joystick data
            if(command == 8'd3) begin
                if(state == 4'd0) device <= data_in;
                if(state == 4'd1) begin
                    if(device == 8'd0) joystick0 <= data_in;
                    if(device == 8'd1) joystick1 <= data_in;
                end 
            end

            // CMD 4: send digital joystick data to MCU
            if(command == 8'd4) begin
                if(state == 4'd0) irq_enable <= 1'b1;    // (re-)enable interrupt
                data_out <= {2'b00, db9_portD };               
            end

        end
      end else begin // if (data_in_strobe)
        mouse_div <= mouse_div + 12'd1;      
        if(mouse_div == 12'd0) begin
            if(mouse_x_cnt != 8'd0) begin
                if(mouse_x_cnt[7]) begin
                    mouse_x_cnt <= mouse_x_cnt + 8'd1;
                    // 2 bit gray counter to emulate the mouse's light barriers
                    mouse_x[0] <=  mouse_x[1];
                    mouse_x[1] <= ~mouse_x[0];            
                end else begin
                    mouse_x_cnt <= mouse_x_cnt - 8'd1;
                    mouse_x[0] <= ~mouse_x[1];
                    mouse_x[1] <=  mouse_x[0];
                end         
            end // if (mouse_x_cnt != 8'd0)
            
            if(mouse_y_cnt != 8'd0) begin
                if(mouse_y_cnt[7]) begin
                    mouse_y_cnt <= mouse_y_cnt + 8'd1;
                    mouse_y[0] <= ~mouse_y[1];            
                    mouse_y[1] <=  mouse_y[0];
                end else begin
                    mouse_y_cnt <= mouse_y_cnt - 8'd1;
                    mouse_y[0] <=  mouse_y[1];
                    mouse_y[1] <= ~mouse_y[0];
                end         
            end
	end
      end
   end
end
    
endmodule
