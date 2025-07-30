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
extern uint8_t module_data[], module_data_end[];

extern void muson(void);

/* prepare the given mod data for replay with the Wizzcat routine: */
/* - convert from original 15 sample format to newer 31 sample format if needed */
/* - adjust repeat lengths */

extern uint8_t *module_ptr, *workspc;

void prepare(uint8_t *data, int len) {
  // check for valid tag (new format only)
  if( (*(uint32_t*)(data+1080) != 'M.K.') &&
      (*(uint32_t*)(data+1080) != 'M!K!') && 
      (*(uint32_t*)(data+1080) != 'FLT4') ) {

    /* copy pattern and sample data from 600 to 1084 */
    bcopy(data+600, data+1084, len-600);

    /* copy number of patterns, jump position and pattern table*/
    bcopy(data+470, data+950, 128+2);

    /* clear additional 16 sample entries */
    bzero(data+20+15*30, 16*30);    

    /* set tag (not really needed by wizzcat player */
    *(uint32_t*)(data+1080) = 'M.K.';
  }

  /* check for sample repeat len being 0 */
  uint8_t *p = data+20;
  for(int i=0;i<31;i++,p+=30)
    if(*(uint16_t*)(p+28) == 0)
      *(uint16_t*)(p+28) = 1;

  module_ptr = data;
}

#define CHK(n,f) { OSErr e = f; if(e) { wprintf("%s failed with error %d\n", n, e); return NULL; } }

uint8_t *load_mod(void) {
  short int vref = -1;
  short int ref;
  Str255 volName;
  Str255 name;

  CHK("GetVol()", GetVol(volName, &vref));

  // append song name to volume name
  memcpy(name, volName, volName[0]+1);  
  name[name[0]+1] = 0;    
  strcat(name+1, ":song.mod");
  name[0] = strlen(name+1);
  
  wprintf("\nLoading file: %S\n", name);

  CHK("FSOpen()", FSOpen(name, vref, &ref));

  // get file size
  CHK("SetFPos()", SetFPos(ref, fsFromLEOF, 0));
  long size = -1;
  CHK("GetFPos()", GetFPos(ref, &size));
  CHK("SetFPos()", SetFPos(ref, fsFromStart, 0));

  wprintf("File size: %d bytes\n", size);  

  /* prepare() needs some additional 484 bytes and there needs */
  /* to be 64k extra "workspace" for the wizzcat init routines */
  uint8_t *data = NewPtr(size+484+4*16384+2);

  if(!data) {
    wprintf("No enough memory\n");
    return NULL;
  }
  
  CHK("FSRead()", FSRead(ref, &size, data));
  
  CHK("FSClose()", FSClose(ref));

  prepare(data, size);
  workspc = data+size+484+4*16384+2;
  
  return data;
}

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
  vbl_test_var = 0;

  /* try to load a mod and use the built-in one if that fails */
  if(!load_mod())  
    prepare(module_data, module_data_end - module_data);
  
  wprintf("\nTitle: %s\n", module_ptr);   // bytes 0..19 are 0 terminated name

  muson();

  /* playback now runs in the background in the VBL */
    
  for(;;)
    wprintf("Playing %d:%d.%d ...\r",
	    vbl_test_var/3600, ((vbl_test_var%3600)/60), (vbl_test_var%60)/6);
  
  return 0;
}
