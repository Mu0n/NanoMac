/*
 macplus_keymap.v
 
 table to translate from FPGA Compantions key codes into
 Mac Plus key codes. The incoming FPGA Companion codes
 are mainly the USB HID key codes with the modifier keys
 mapped into the 0x68+ range.

 https://www.bigmessowires.com/2011/08/28/plus-too-keyboard-and-mouse/
 https://github.com/tmk/tmk_keyboard/wiki/Apple-M0110-Keyboard-Protocol 
*/

module keymap (
  input [6:0]  code,
  output [8:0] mac
);

assign mac = 
                                  // 00: NoEvent
                                  // 01: Overrun Error
                                  // 02: POST fail
                                  // 03: ErrorUndefined
  // characters
  (code == 7'h04)?{2'd0,7'h01}:   // 04: a
  (code == 7'h05)?{2'd0,7'h17}:   // 05: b
  (code == 7'h06)?{2'd0,7'h11}:   // 06: c
  (code == 7'h07)?{2'd0,7'h05}:   // 07: d
  (code == 7'h08)?{2'd0,7'h1d}:   // 08: e
  (code == 7'h09)?{2'd0,7'h07}:   // 09: f
  (code == 7'h0a)?{2'd0,7'h0b}:   // 0a: g
  (code == 7'h0b)?{2'd0,7'h09}:   // 0b: h
  (code == 7'h0c)?{2'd0,7'h45}:   // 0c: i
  (code == 7'h0d)?{2'd0,7'h4d}:   // 0d: j
  (code == 7'h0e)?{2'd0,7'h51}:   // 0e: k
  (code == 7'h0f)?{2'd0,7'h4b}:   // 0f: l
  (code == 7'h10)?{2'd0,7'h5d}:   // 10: m
  (code == 7'h11)?{2'd0,7'h5b}:   // 11: n
  (code == 7'h12)?{2'd0,7'h3f}:   // 12: o
  (code == 7'h13)?{2'd0,7'h47}:   // 13: p
  (code == 7'h14)?{2'd0,7'h19}:   // 14: q
  (code == 7'h15)?{2'd0,7'h1f}:   // 15: r
  (code == 7'h16)?{2'd0,7'h03}:   // 16: s
  (code == 7'h17)?{2'd0,7'h23}:   // 17: t
  (code == 7'h18)?{2'd0,7'h41}:   // 18: u
  (code == 7'h19)?{2'd0,7'h13}:   // 19: v
  (code == 7'h1a)?{2'd0,7'h1b}:   // 1a: w
  (code == 7'h1b)?{2'd0,7'h0f}:   // 1b: x
  (code == 7'h1c)?{2'd0,7'h21}:   // 1c: y
  (code == 7'h1d)?{2'd0,7'h0d}:   // 1d: z

  // top number key row
  (code == 7'h1e)?{2'd0,7'h25}:   // 1e: 1
  (code == 7'h1f)?{2'd0,7'h27}:   // 1f: 2
  (code == 7'h20)?{2'd0,7'h29}:   // 20: 3
  (code == 7'h21)?{2'd0,7'h2b}:   // 21: 4
  (code == 7'h22)?{2'd0,7'h2f}:   // 22: 5
  (code == 7'h23)?{2'd0,7'h2d}:   // 23: 6
  (code == 7'h24)?{2'd0,7'h35}:   // 24: 7
  (code == 7'h25)?{2'd0,7'h39}:   // 25: 8
  (code == 7'h26)?{2'd0,7'h33}:   // 26: 9
  (code == 7'h27)?{2'd0,7'h3b}:   // 27: 0
  
  // other keys
  (code == 7'h28)?{2'd0,7'h49}:   // 28: return
  (code == 7'h29)?{2'd0,7'h7f}:   // 29: esc
  (code == 7'h2a)?{2'd0,7'h67}:   // 2a: backspace
  (code == 7'h2b)?{2'd0,7'h61}:   // 2b: tab		  
  (code == 7'h2c)?{2'd0,7'h63}:   // 2c: space

  (code == 7'h2d)?{2'd0,7'h37}:   // 2d: -
  (code == 7'h2e)?{2'd0,7'h31}:   // 2e: =
  (code == 7'h2f)?{2'd0,7'h43}:   // 2f: [			  
  (code == 7'h30)?{2'd0,7'h3d}:   // 30: ]
  (code == 7'h31)?{2'd0,7'h55}:   // 31: backslash 
  (code == 7'h32)?{2'd0,7'h7f}:   // 32: EUR-1
  (code == 7'h33)?{2'd0,7'h53}:   // 33: ;
  (code == 7'h34)?{2'd0,7'h4f}:   // 34: ' 
  (code == 7'h35)?{2'd0,7'h65}:   // 35: `
  (code == 7'h36)?{2'd0,7'h57}:   // 36: ,
  (code == 7'h37)?{2'd0,7'h5f}:   // 37: .
  (code == 7'h38)?{2'd0,7'h59}:   // 38: /
  (code == 7'h39)?{2'd0,7'h73}:   // 39: caps lock

  // function keys
  (code == 7'h3a)?{2'd0,7'h7f}:   // 3a: F1
  (code == 7'h3b)?{2'd0,7'h7f}:   // 3b: F2
  (code == 7'h3c)?{2'd0,7'h7f}:   // 3c: F3
  (code == 7'h3d)?{2'd0,7'h7f}:   // 3d: F4
  (code == 7'h3e)?{2'd0,7'h7f}:   // 3e: F5
  (code == 7'h3f)?{2'd0,7'h7f}:   // 3f: F6
  (code == 7'h40)?{2'd0,7'h7f}:   // 40: F7
  (code == 7'h41)?{2'd0,7'h7f}:   // 41: F8
  (code == 7'h42)?{2'd0,7'h7f}:   // 42: F9
  (code == 7'h43)?{2'd0,7'h7f}:   // 43: F10
                                  // 44: F11
                                  // 45: F12

                                  // 46: PrtScr
                                  // 47: Scroll Lock
                                  // 48: Pause
  (code == 7'h49)?{2'd3,7'h11}:   // 49: Insert -> KP =
  (code == 7'h4a)?{2'd0,7'h7f}:   // 4a: Home
  (code == 7'h4b)?{2'd0,7'h7f}:   // 4b: PageUp
  (code == 7'h4c)?{2'd1,7'h0f}:   // 4c: Delete -> KP Clr
  (code == 7'h4d)?{2'd0,7'h7f}:   // 4d: End
  (code == 7'h4e)?{2'd0,7'h7f}:   // 4e: PageDown
  
  // cursor keys
  (code == 7'h4f)?{2'd1,7'h05}:   // 4f: right
  (code == 7'h50)?{2'd1,7'h0d}:   // 50: left
  (code == 7'h51)?{2'd1,7'h11}:   // 51: down
  (code == 7'h52)?{2'd1,7'h1b}:   // 52: up
  
                                  // 53: Num Lock

  // keypad
  (code == 7'h54)?{2'd3,7'h1b}:   // 54: KP /
  (code == 7'h55)?{2'd3,7'h05}:   // 55: KP *
  (code == 7'h56)?{2'd1,7'h1d}:   // 56: KP -
  (code == 7'h57)?{2'd3,7'h0d}:   // 57: KP +
  (code == 7'h58)?{2'd1,7'h19}:   // 58: KP Enter
  (code == 7'h59)?{2'd1,7'h27}:   // 59: KP 1
  (code == 7'h5a)?{2'd1,7'h29}:   // 5a: KP 2
  (code == 7'h5b)?{2'd1,7'h2b}:   // 5b: KP 3
  (code == 7'h5c)?{2'd1,7'h2d}:   // 5c: KP 4
  (code == 7'h5d)?{2'd1,7'h2f}:   // 5d: KP 5
  (code == 7'h5e)?{2'd1,7'h31}:   // 5e: KP 6
  (code == 7'h5f)?{2'd1,7'h33}:   // 5f: KP 7
  (code == 7'h60)?{2'd1,7'h37}:   // 60: KP 8
  (code == 7'h61)?{2'd1,7'h39}:   // 61: KP 9
  (code == 7'h62)?{2'd1,7'h25}:   // 62: KP 0
  (code == 7'h63)?{2'd1,7'h03}:   // 63: KP .
  (code == 7'h64)?{2'd0,7'h7f}:   // 64: EUR-2

  // remapped modifier keys
  (code == 7'h68)?{2'd0,7'h75}:   // left ctrl
  (code == 7'h69)?{2'd0,7'h71}:   // left shift
  (code == 7'h6a)?{2'd0,7'h6f}:   // left alt
  (code == 7'h6b)?{2'd0,7'h6f}:   // left meta
  (code == 7'h6c)?{2'd0,7'h75}:   // right ctrl
  (code == 7'h6d)?{2'd0,7'h71}:   // right shift
  (code == 7'h6e)?{2'd0,7'h69}:   // right alt
  (code == 7'h6f)?{2'd0,7'h69}:   // right meta
  { 2'd0, 7'h7f };   

endmodule
  
