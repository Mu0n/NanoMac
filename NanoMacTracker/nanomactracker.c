/*
  nanomactracker.c
*/

#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <Files.h>
#include <stdint.h>
#include <stdbool.h>

#include <Quickdraw.h>
#include <Dialogs.h>
#include <Fonts.h>
#include <StandardFile.h>

pascal void ButtonFrameProc(DialogRef dlg, DialogItemIndex itemNo) {
  DialogItemType type;
  Handle itemH;
  Rect box;
  
  GetDialogItem(dlg, 1, &type, &itemH, &box);
  InsetRect(&box, -4, -4);
  PenSize(3,3);
  FrameRoundRect(&box,16,16);
}

volatile uint32_t vbl_test_var = 0;
Str255 name;
uint8_t *data;

// A demo mod is hard coded into the assembler file
//extern uint8_t module_data[], module_data_end[];

extern void muson(void);
extern void musoff(void); // Disables and unlinks VBL.
extern void musdis(void);
extern void musen(void);
extern void vblHook(void);

extern uint32_t samp1;
uint32_t gOrigSamp1; // 

/**
 * Skips Vbl playback if it had been playing, but doesn't unlink the VBL.
 */
bool VblSkip(bool aSkip)
{
	if(aSkip==false && samp1==0) {
		samp1=gOrigSamp1; // restore VBL playback.
	}
	else if(aSkip==true && samp1) {
		gOrigSamp1=samp1;
		samp1=0; // Disable.
	}
	return (samp1==0)?true:false;
}

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
    BlockMove(data+600, data+1084, len-600);

    /* copy number of patterns, jump position and pattern table*/
    BlockMove(data+470, data+950, 128+2);

    /* clear additional 16 sample entries */
    //bzero(data+20+15*30, 16*30);     //Block was cleared.

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

#define CHK(n,f) { OSErr e = f; if(e) { /* wprintf("%s failed with error %d\n", n, e); */ return NULL; } }

uint8_t *load_mod() {
  short int ref;
  //Str255 volName;
  //Str255 name;
  SFTypeList myTypes;

  SFReply reply; //used to fetch the answer of a standard file get dialog
  Point where={50,50}; //location to draw said dialog
  
  
  SFGetFile(where,"\pSelect a MOD file",0L,-1,myTypes,0L,&reply);
  
  if(reply.good) {
		strcat(name, reply.fName);
		CHK("FSOpen()", FSOpen(reply.fName, reply.vRefNum, &ref));
		
		// get file size
		CHK("SetFPos()", SetFPos(ref, fsFromLEOF, 0));
		long size = -1;
		CHK("GetFPos()", GetFPos(ref, &size));
		CHK("SetFPos()", SetFPos(ref, fsFromStart, 0));
		
		// wprintf("File size: %d bytes\n", size);  
		
		/* prepare() needs some additional 484 bytes and there needs */
		/* to be 64k extra "workspace" for the wizzcat init routines */
		if(data != NULL) {
			DisposePtr(data);
		}
		data = NewPtrClear(size+484+4*16384+2);
		
		if(!data) {
			/* wprintf("No enough memory\n"); */
			return NULL;
		}
		
		CHK("FSRead()", FSRead(ref, &size, data));
		
		CHK("FSClose()", FSClose(ref));
		
		prepare(data, size);
		workspc = data+size+484+4*16384+2;
		return data;
 	}
	return NULL;
}

void set_text(DialogPtr dlg, int item, char *text) {
  static char str[255] = "\0Hallo!";
  
  DialogItemType type;
  Handle itemH;
  Rect box;

  ControlHandle info;
  GetDialogItem(dlg, item, &type, &itemH, &box);
  info = (ControlHandle)itemH;
  str[0] = strlen(text);
  memcpy(str+1, text, str[0]);
  SetControlTitle(info, str);
}

int main(int argc, char** argv)
{
	InitGraf(&qd.thePort);
	InitFonts();
	InitWindows();
	InitMenus();
	TEInit();
	InitDialogs(NULL);
	
	
	DialogPtr dlg = GetNewDialog(128,0,(WindowPtr)-1);
	InitCursor();
	
	DialogItemType type;
	Handle itemH;
	Rect box;
	
	// bold border for Quit button
	GetDialogItem(dlg, 2, &type, &itemH, &box);
	SetDialogItem(dlg, 2, type, (Handle) NewUserItemUPP(&ButtonFrameProc), &box);
	
	// ==== init tracker ====
	
	// this test variable is just incremented by the player code
	// every vbl and thus counts at 60hz
	vbl_test_var = 0;

	musdis();	// stop audio.
	VblSkip(true); // force vbl not to play anything if it was on.
	vblHook();	// hook in the new VBL.
  
	/* playback now runs in the background in the VBL */
	
	short item;
	do {
		ModalDialog(NULL, &item);
		if(item == 5) //a new song is selected
		{
			musdis();	// stop audio in either case.
			VblSkip(true);	// force VBL to skip.
			
			/* try to load a mod and use the built-in one if that fails */
			if(load_mod()) 
			{	  // we want to play the audio.
				//swap in the name in the dialog box
				GetDialogItem(dlg, 4, &type, &itemH, &box);
				SetDialogItemText(itemH,name);
				muson(); // Calc tables & clr sound buffer.
				musen();	// enable audio.
				VblSkip(false); // start the VBL processing.
			}
		}
	}while(item != 1);
	
	musoff(); // restore VBL and audio.
	
	FlushEvents(everyEvent, -1);
	return 0;
}
