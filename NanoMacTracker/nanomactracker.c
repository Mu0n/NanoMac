/*
  nanomactracker.c
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <Files.h>

#include "font_16x8.h"

// variable counted up by vbl irq handler
volatile uint32_t vbl_test_var = 0;

/* simple text output bypassing all operating system */
static uint32_t *screen_ptr = (uint32_t*)0x3FA700;

void mwrite(char *str, int len) {
  static uint16_t x = 0, y = 0;

  void scroll_up(void) {
    uint32_t *dst = screen_ptr;
    uint32_t *src = screen_ptr + 16*512/32;
    for(int i=0;i<(342-16)*512/32;i++)
      *dst++ = *src++;

    // erase bottom row
    for(int i=0;i<16*512/32;i++)
      *dst++ = 0;    
  }
  
  while(len) {
    if(*str == '\r') {
      x=0;
    } else if(*str == '\n') {
      x=0;
      y++;

      if(y > (342-16)/16) {
	scroll_up();
	y -= 1;
      }
    } else {
      // draw a single char
      uint8_t *dst = (uint8_t *)screen_ptr + 16*512/8 * y + x;
      const uint8_t *src = bin2c_font_16x8_fnt + 16 * *str;

      for(int i=0;i<16;i++,dst+=512/8)
	*dst = *src++;      

      x++;
      if(x == 512/8) {
	x = 0;
	y++;

	if(y > (342-16)/16) {
	  scroll_up();
	  y -= 1;
	}
      }
    }
    
    str++; len--;
  }
}

void wprintf(char *fmt, ...) {
  va_list ap;

  va_start(ap, fmt);

  // walk over format string
  while(*fmt) {  
    char *p = fmt;
    while(*p && *p != '%') p++;

    mwrite(fmt, p-fmt);

    // end of string reached?
    if(!*p) return;

    p++;  // skip '%'
    if(!*p) return;
    
    switch(*p) {
    case 'd': {
      char b[16];
      int32_t i = va_arg(ap, int32_t);
      itoa(i,b,10);
      mwrite(b, strlen(b));
    } break;
      
    case 'x': {
      char b[16];
      int32_t i = va_arg(ap, int32_t);
      itoa(i,b,16);
      mwrite(b, strlen(b));
    } break;

    case 's':
      char *s = va_arg(ap, char*);
      mwrite(s, strlen(s));
      break;

    case 'S':   // pascal string
      char *S = va_arg(ap, char*);
      mwrite(S+1, S[0]);
      break;

    case '%':
      mwrite(p,1);
      break;
    }
    
    p++;
    if(!*p) return;
    fmt = p;
  }

  va_end(ap);
}

// for now the mod is hard coded into the assembler file
// https://moddingwiki.shikadi.net/wiki/MOD_Format
// https://github.com/lclevy/unmo3/blob/master/spec/mod.txt
extern uint8_t module_data[];

extern void muson(void);

int main(int argc, char** argv) {

  // no visible mouse cursor
  HideCursor();
  
  // clear background
  uint32_t *p = screen_ptr;
  for(int i=0;i<512*342/32;i++) *p++ = 0;
  
  wprintf("NanoMacTracker\n");
  wprintf("==============\n");
  wprintf("Wizzcat protracker ported to classic mac\n");
  wprintf("NanoMac version by Till Harbaum\n");

  wprintf("\nSong: %s\n", module_data);   // bytes 0..19 are 0 terminated name

  vbl_test_var = 0;
  muson();

  /* playback now runs in the background in the VBL */
  for(;;)
    wprintf("Playing %d:%d.%d ...\r",
	    vbl_test_var/3600, ((vbl_test_var%3600)/60), (vbl_test_var%60)/6);
  
  return 0;
}
