/*----------------------------------------------------------------------*/
/* 	Replay STe							*/
/* 	by WizzCat the 21st of May 1991					*/
/*----------------------------------------------------------------------*/
/* Uses no registers							*/
/*									*/
/* Replay is started by calling MUSON in supervisor mode. Returns with	*/
/* timer A running. Calling MUSOFF will stop music.			*/
/*									*/
/* This routine needs some workspace after the module to work properly.	*/
/* We've set it to 16k, some modules needs more, some need less. If the	*/
/* workspace is too small, initialization will hang on an ILLEGAL	*/
/* instruction. Adjust workspace size to fit the specific module.	*/
/*									*/
/* MVOL = Main volume	  (Unnecessary to adjust. $80 default)		*/
/* FREQ = replay frequency (See below)					*/
/*----------------------------------------------------------------------*/
/* This version has been adapted to work on classic Apple Macs like     */
/* the 512k or Plus							*/
/*----------------------------------------------------------------------*/

.text
	
.equ MVOL,  0x80

.ifdef STE
.equ FREQ,  2                           /*  0=6.259, 1=12.517, 2=25.036 */
                                        /*  3=50.072 (MegaSTe/TT)       */

.if (FREQ == 0)
.equ PARTS, 5-1                         /* 6.259 */
.equ LEN,   25
.equ INC,   0x023BF313                  /* 3579546/6125*65536 */
.else
.if FREQ == 1
.equ PARTS, 5-1                         /* 12.517 */
.equ LEN,   50
.equ INC,   0x011DF989                  /* 3579546/12517*65536 */
.else
.if (FREQ == 2)
.equ PARTS, 5-1                         /* 25.035 */
.equ LEN,   100
.equ INC,   0x008EFB4E                  /* 3579546/25035*65536 */
.else
.if FREQ == 3
.equ PARTS, 5-1                         /* 50.072 */
.equ LEN,   200
.equ INC,   0x00477CEC                  /* 3579546/50072*65536 */
.else
.err
.endif
.endif
.endif
.endif

.else
/* Mac */
.equ PARTS, 6	
.equ LEN,   370
.equ INC,   (3579546/22250*65536)
.endif
	
/* ================================================================================ */
/* ================================================================================ */

.ifndef STE
	.globl muson

vbl_handler:
.ifdef FORWARD_TO_ORIG_IRQ
	/* check if this actally is a vbl irq. */
 	btst.b #1, 0xefe1fe + 0x1a00
 	beq.s      cont_orig
.endif
	
	/* save all registers that may be clobbered */
	movem.l	%d0-%d1/%a0-%a1,-(%sp)

	/* this initial copy needs to run as fast as possible to make sure the first */
	/* byte is being written before the hardware reads it */

	/* copy from audio buffer to hardware */
	move.l  #0x3ffd00, %a0    
	move.l  samp1, %a1 
        move.w  #45, %d0  /* 46*8 = 368 bytes + 2 */
cp:
	/* copy 8 samples per iteration */
        move.l   (%a1)+,%d1
        movep.l  %d1,0(%a0)
        move.l  (%a1)+,%d1
        movep.l %d1,8(%a0)
        add.l   #16,%a0
        dbra    %d0,cp     
        move.b  (%a1)+,(%a0)   /* byte 369 */
        move.b  (%a1)+,2(%a0)  /* byte 370 */
	/* audio has been copied to hardware buffer */
	
	/* call wizzcat main mod decoder routine */
        bsr	  stereo
	add.l #1, vbl_test_var	
	
	movem.l (%sp)+,%d0-%d1/%a0-%a1
	
.ifndef FORWARD_TO_ORIG_IRQ
	/* =================== exit  ========================= */     
	move.b 	#2, 0xefe1fe+0x1a00   /* ack vbl irq */
	rte
.else
	/* =================== exit into original handler ========================= */     
cont_orig:
	/* move the address of the original handler into the stack, */
	/* so we can rts into the old handler */
	move.l  vbl_orig,-(%sp)
	rts
.endif
.endif
	
/* ================================================================================ */
/* ================================================================================ */

.ifdef STE
/*------------------------------- Cut here ------------------------------*/
/*                   Rout to test replay. May omitted.                   */

        pea     muson(%pc)
        move.w  #0x26,-(%sp)
        trap    #14                     /* Supexec - start music */
        addq.w  #6,%sp

        move.w  #7,-(%sp)
        trap    #1

        pea     musoff(%pc)
        move.w  #0x26,-(%sp)
        trap    #14                     /* Supexec - stop music */
        addq.w  #6,%sp

        pea     0x4C0000
        trap    #1                      /* Terminate */
	
/*------------------------------- Cut here ------------------------------*/
.endif
	
/*---------------------------------------------------- Interrupts on/off --*/
.ifdef FORWARD_TO_ORIG_IRQ
vbl_orig:ds.l	1
.endif
	
muson:
.ifndef STE
	movem.l %d0-%a6,-(%sp)
.endif	
	bsr     vol                     /* Calculate volume tables */
        bsr     incrcal                 /* Calculate tonetables */

        jsr     init                    /* Initialize music */
        jsr     prepare                 /* Prepare samples */
.ifdef STE
        move    #0x2700,%sr

        bset    #5,0xFFFFFA07.w         /* enable MFP timer a irq */
        bset    #5,0xFFFFFA13.w         /* mask MFP timer a irq */

        clr.b   0xFFFFFA19.w            /* timer a divider, 0=stop */
        move.b  #1,0xFFFFFA1F.w         /* timer a data */
        move.b  #8,0xFFFFFA19.w         /* timer a event count modeon STE DMA XSINT */

        move.l  0x0134.w,oldtima        /* save old timer a vector */
        move.l  #stereo,0x0134.w        /* set new timer a vector */

        move.b  #FREQ,0xFFFF8921.w      /* STE audio DMA Frequency */

        lea     0xFFFF8907.w,%a0        /* STE audio DMA start address */

        move.l  #sample1,%d0            /* sample start */
        move.b  %d0,(%a0)               /* set STE audio DMA start address low byte */
        lsr.w   #8,%d0
        move.l  %d0,-5(%a0)             /* -"- set start mid and high byte */

        move.l  #sample1+LEN*2,%d0      /* sample end */
        move.b  %d0,12(%a0)             /* set STE audio DMA end address low byte */
        lsr.w   #8,%d0
        move.l  %d0,7(%a0)              /* -"- set end mid and high byte */

        move.b  #3,0xFFFF8901.w         /* start DMA audio engine */

        move    #0x2300,%sr
.else
.ifdef FORWARD_TO_ORIG_IRQ
	move.l	0x64, vbl_orig          /* save old handler */
.endif	
	move.l  #vbl_handler, 0x64 	/* overwrite original handler */

	bclr.b  #7,0xefe1fe             /* set pb[7] = 0 to enable audio output */
 	bset.b  #3,0xefe1fe + 0x1e00    /* snd alt = 1 */

	move.b  #0x7d,0xefe1fe + 0x1c00 /* disable all interrupts but vbl */

	movem.l (%sp)+,%d0-%a6
.endif	
        rts

musoff:
.ifdef STE
	move    #0x2700,%sr

        clr.b   0xFFFFFA19.w             /* Stop timers */

        move.l  oldtima(%pc),0x0134.w     /* Restore everything */

        bclr    #5,0xFFFFFA07.w
        bclr    #5,0xFFFFFA13.w

        clr.b   0xFFFF8901.w             /* Stop DMA */

        move    #0x2300,%sr
.endif
        rts

.ifdef STE
oldtima:DC.L 0
.endif
	
/*--------------------------------------------------------- Volume table --*/
vol:	moveq	#64,%d0
	lea	vtabend(%pc),%a0

ploop:	move.w	#255,%d1
mloop:	move.w	%d1,%d2
	ext.w	%d2
	muls	%d0,%d2
	divs	#MVOL,%d2		/* <---- Master volume*/
	move.b	%d2,-(%a0)
	dbra	%d1,mloop
	dbra	%d0,ploop

	rts

vtab:	DS.B 65*256
vtabend:	

/*------------------------------------------------------ Increment-table --*/
incrcal:lea	stab(%pc),%a0
	move.w	#0x30,%d1
	move.w	#0x039F-0x30,%d0
	move.l	#INC,%d2

recalc:	swap	%d2
	moveq	#0,%d3
	move.w	%d2,%d3
	divu	%d1,%d3
	move.w	%d3,%d4
	swap	%d4

	swap	%d2
	move.w	%d2,%d3
	divu	%d1,%d3
	move.w	%d3,%d4
	move.l	%d4,(%a0)+

	addq.w	#1,%d1
	dbra	%d0,recalc
	rts

itab:	DS.L 0x30
stab:	DS.L 0x03A0-0x30

/*-------------------------------------------------------- DMA interrupt --*/
stereo:
.ifdef STE
	move    #0x2500,%sr
        bclr    #5,0xFFFFFA0F.w        /* acknowldge MFP interrupt */
.endif
        movem.l %d0-%a6,-(%sp)

	/* On mac we actually only need one buffer since we copy to */
	/* the hardware and afterwards the buffer can be overwritten */
	
.ifdef STE
        move.l  samp1(%pc),%d0         /* swap sample buffer pointers */
        move.l  samp2(%pc),samp1
        move.l  %d0,samp2

	/* restart STE DMA audio */
	lea     0xFFFF8907.w,%a0       /* STE DMA sound start address */

        move.l  samp1(%pc),%d0         /* set dma start */ 
        move.b  %d0,(%a0)              /* low, ... */
        lsr.w   #8,%d0
        move.l  %d0,-5(%a0)            /* ... mid and high */

        move.l  samp1(%pc),%d0         /* set dma end */ 
        add.l   #LEN*2,%d0
        move.b  %d0,12(%a0)            /* low, ... */
        lsr.w   #8,%d0
        move.l  %d0,7(%a0)             /* ... mid and high */
.endif

.ifdef STE
        /* Sample buffer lasts 1/250 second */
        /* Run every 5 buffers to update at 50Hz */
 	subq.w	#1,count
 	bpl.s	nomus

 	move.w	#PARTS,count
.else
	/* Mac runs in vbl at 60Hz. So skip every 6th run to */
	/* update at 50Hz */
 	subq.w	#1,count
	bpl.s   domus
	move.w	#PARTS,count
	bra.s	nomus
domus:	
.endif
	
	bsr	music

nomus:	lea	itab(%pc),%a5
	lea	vtab(%pc),%a3
	moveq	#0,%d0
	moveq	#0,%d4

v1:	movea.l	wiz2lc(%pc),%a0

	move.w	wiz2pos(%pc),%d0
	move.w	wiz2frc(%pc),%d1

	move.w	aud2per(%pc),%d7
	add.w	%d7,%d7
	add.w	%d7,%d7
	move.w	0(%a5,%d7.w),%d2

	movea.w	2(%a5,%d7.w),%a4

	move.w	aud2vol(%pc),%d7
	asl.w	#8,%d7
	lea	0(%a3,%d7.w),%a2


	movea.l	wiz3lc(%pc),%a1

	move.w	wiz3pos(%pc),%d4
	move.w	wiz3frc(%pc),%d5

	move.w	aud3per(%pc),%d7
	add.w	%d7,%d7
	add.w	%d7,%d7
	move.w	0(%a5,%d7.w),%d6
	movea.w	2(%a5,%d7.w),%a5

	move.w	aud3vol(%pc),%d7
	asl.w	#8,%d7
	lea	0(%a3,%d7.w),%a3

	movea.l	samp1(%pc),%a6
	moveq	#0,%d3

	.rept LEN
	add.w	%a4,%d1
	addx.w	%d2,%d0
	add.w	%a5,%d5
	addx.w	%d6,%d4
	move.b	0(%a0,%d0.l),%d3
	move.b	0(%a2,%d3.w),%d7
	move.b	0(%a1,%d4.l),%d3
	add.b	0(%a3,%d3.w),%d7
.ifdef STE
	/* write out first channel data to odd addresses */
	move.w	%d7,(%a6)+
.else
	/* write out first channel data as unsigned byte */
	eor.b	#0x80,%d7       /* convert to unsigned */
	lsr.b   #1,%d7          /* divide by two to allow adding of second channel */
	move.b	%d7,(%a6)+
.endif	
	.endr

	cmp.l	wiz2len(%pc),%d0
	blt.s	ok2
	sub.w	wiz2rpt(%pc),%d0

ok2:	move.w	%d0,wiz2pos
	move.w	%d1,wiz2frc

	cmp.l	wiz3len(%pc),%d4
	blt.s	ok3
	sub.w	wiz3rpt(%pc),%d4

ok3:	move.w	%d4,wiz3pos
	move.w	%d5,wiz3frc



	lea	itab(%pc),%a5
	lea	vtab(%pc),%a3
	moveq	#0,%d0
	moveq	#0,%d4

v2:	movea.l	wiz1lc(%pc),%a0

	move.w	wiz1pos(%pc),%d0
	move.w	wiz1frc(%pc),%d1

	move.w	aud1per(%pc),%d7
	add.w	%d7,%d7
	add.w	%d7,%d7
	move.w	0(%a5,%d7.w),%d2
	movea.w	2(%a5,%d7.w),%a4

	move.w	aud1vol(%pc),%d7
	asl.w	#8,%d7
	lea	0(%a3,%d7.w),%a2


	movea.l	wiz4lc(%pc),%a1

	move.w	wiz4pos(%pc),%d4
	move.w	wiz4frc(%pc),%d5

	move.w	aud4per(%pc),%d7
	add.w	%d7,%d7
	add.w	%d7,%d7
	move.w	0(%a5,%d7.w),%d6
	movea.w	2(%a5,%d7.w),%a5

	move.w	aud4vol(%pc),%d7
	asl.w	#8,%d7
	lea	0(%a3,%d7.w),%a3

	movea.l	samp1(%pc),%a6
	moveq	#0,%d3

	.rept LEN
	add.w	%a4,%d1
	addx.w	%d2,%d0
	add.w	%a5,%d5
	addx.w	%d6,%d4
	move.b	0(%a0,%d0.l),%d3
	move.b	0(%a2,%d3.w),%d7
	move.b	0(%a1,%d4.l),%d3
	add.b	0(%a3,%d3.w),%d7
.ifdef STE
	/* write second channel data to every second byte */
	move.b	%d7,(%a6)    /* write second channel sample data */
	addq.w	#2,%a6
.else
	eor.b   #0x80,%d7    /* convert to unsigned */
	lsr.b   #1,%d7       /* divide by 2 */
	add.b	%d7,(%a6)+   /* add to first channel sample data */	
.endif
	.endr

	cmp.l	wiz1len(%pc),%d0
	blt.s	ok1
	sub.w	wiz1rpt(%pc),%d0

ok1:	move.w	%d0,wiz1pos
	move.w	%d1,wiz1frc

	cmp.l	wiz4len(%pc),%d4
	blt.s	ok4
	sub.w	wiz4rpt(%pc),%d4

ok4:	move.w	%d4,wiz4pos
	move.w	%d5,wiz4frc

	movem.l	(%sp)+,%d0-%a6
.ifdef STE
        rte
.else
	rts
.endif

/*-------------------------------------------- Hardware-registers & data --*/
count:	DC.W PARTS
	
wiz1lc:	DC.L sample1
wiz1len:DC.L 0
wiz1rpt:DC.W 0
wiz1pos:DC.W 0
wiz1frc:DC.W 0

wiz2lc:	DC.L sample1
wiz2len:DC.L 0
wiz2rpt:DC.W 0
wiz2pos:DC.W 0
wiz2frc:DC.W 0

wiz3lc:	DC.L sample1
wiz3len:DC.L 0
wiz3rpt:DC.W 0
wiz3pos:DC.W 0
wiz3frc:DC.W 0

wiz4lc:	DC.L sample1
wiz4len:DC.L 0
wiz4rpt:DC.W 0
wiz4pos:DC.W 0
wiz4frc:DC.W 0

aud1lc:	DC.L dummy
aud1len:DC.W 0
aud1per:DC.W 0
aud1vol:DC.W 0
	DS.W 3

aud2lc:	DC.L dummy
aud2len:DC.W 0
aud2per:DC.W 0
aud2vol:DC.W 0
	DS.W 3

aud3lc:	DC.L dummy
aud3len:DC.W 0
aud3per:DC.W 0
aud3vol:DC.W 0
	DS.W 3

aud4lc:	DC.L dummy
aud4len:DC.W 0
aud4per:DC.W 0
aud4vol:DC.W 0

dmactrl:DC.W 0

dummy:	DC.L 0

.ifdef STE
/* two 2*8 bit stereo buffers for STE */	
samp1:	DC.L sample1
samp2:	DC.L sample2

sample1:DS.W LEN
sample2:DS.W LEN
.else
/* one 8 bit mono buffer for Mac */
samp1:	DC.L sample1
sample1:DS.B LEN
.endif	
	
/*========================================================= EMULATOR END ==*/

prepare:lea	workspc,%a6
	movea.l	samplestarts(%pc),%a0
	movea.l	end_of_samples(%pc),%a1

tostack:move.w	-(%a1),-(%a6)
	cmpa.l	%a0,%a1			/* Move all samples to stack*/
	bgt.s	tostack

	lea	samplestarts(%pc),%a2
	lea	module_data(%pc),%a1	/* Module*/
	movea.l	(%a2),%a0		/* Start of samples*/
	movea.l	%a0,%a5			/* Save samplestart in a5*/

	moveq	#30,%d7

roop:	move.l	%a0,(%a2)+		/* Sampleposition*/

	tst.w	0x2A(%a1)
	beq.s	samplok			/* Len=0 -> no sample*/

	tst.w	0x2E(%a1)		/* Test repstrt*/
	bne.s	repne			/* Jump if not zero*/


repeq:	move.w	0x2A(%a1),%d0		/* Length of sample*/
	move.w	%d0,%d4
	subq.w	#1,%d0

	movea.l	%a0,%a4
fromstk:move.w	(%a6)+,(%a0)+		/* Move all samples back from stack*/
	dbra	%d0,fromstk

	bra.s	rep



repne:	move.w	0x2E(%a1),%d0
	move.w	%d0,%d4
	subq.w	#1,%d0

	movea.l	%a6,%a4
get1st:	move.w	(%a4)+,(%a0)+		/* Fetch first part*/
	dbra	%d0,get1st

	adda.w	0x2A(%a1),%a6		/* Move a6 to next sample*/
	adda.w	0x2A(%a1),%a6



rep:	movea.l	%a0,%a5
	moveq	#0,%d1
toosmal:movea.l	%a4,%a3
	move.w	0x30(%a1),%d0
	subq.w	#1,%d0
moverep:move.w	(%a3)+,(%a0)+		/* Repeatsample*/
	addq.w	#2,%d1
	dbra	%d0,moverep
	cmp.w	#320,%d1		/* Must be > 320*/
	blt.s	toosmal

	move.w	#320/2-1,%d2
last320:move.w	(%a5)+,(%a0)+		/* Safety 320 bytes*/
	dbra	%d2,last320

done:	add.w	%d4,%d4

	move.w	%d4,0x2A(%a1)		/* length*/
	move.w	%d1,0x30(%a1)		/* Replen*/
	clr.w	0x2E(%a1)

samplok:lea	0x1E(%a1),%a1
	dbra	%d7,roop

	cmp.l	#workspc,%a0
	bgt.s	nospac

	rts

nospac:	illegal

end_of_samples:	DC.L 0

/*------------------------------------------------------ Main replayrout --*/
init:	lea	module_data(%pc),%a0
	lea	0x03B8(%a0),%a1

	moveq	#0x7F,%d0
	moveq	#0,%d1
loop:	move.l	%d1,%d2
	subq.w	#1,%d0
lop2:	move.b	(%a1)+,%d1
	cmp.b	%d2,%d1
	bgt.s	loop
	dbra	%d0,lop2
	addq.b	#1,%d2

	lea	samplestarts(%pc),%a1
	asl.l	#8,%d2
	asl.l	#2,%d2
	add.l	#0x043C,%d2
	add.l	%a0,%d2
	movea.l	%d2,%a2

	moveq	#0x1E,%d0
lop3:	clr.l	(%a2)
	move.l	%a2,(%a1)+
	moveq	#0,%d1
	move.w	42(%a0),%d1
	add.l	%d1,%d1
	adda.l	%d1,%a2
	adda.l	#0x1E,%a0
	dbra	%d0,lop3

	move.l	%a2,end_of_samples	/**/
	rts

music:	lea	module_data(%pc),%a0
	addq.w	#0x01,counter
	move.w	counter(%pc),%d0
	cmp.w	speed(%pc),%d0
	blt.s	nonew
	clr.w	counter
	bra	getnew

nonew:	lea	voice1(%pc),%a4
	lea	aud1lc(%pc),%a3
	bsr	checkcom
	lea	voice2(%pc),%a4
	lea	aud2lc(%pc),%a3
	bsr	checkcom
	lea	voice3(%pc),%a4
	lea	aud3lc(%pc),%a3
	bsr	checkcom
	lea	voice4(%pc),%a4
	lea	aud4lc(%pc),%a3
	bsr	checkcom
	bra	endr

arpeggio:	
	moveq	#0,%d0
	move.w	counter(%pc),%d0
	divs	#0x03,%d0
	swap	%d0
	tst.w	%d0
	beq.s	arp2
	cmp.w	#0x02,%d0
	beq.s	arp1

	moveq	#0,%d0
	move.b	0x03(%a4),%d0
	lsr.b	#4,%d0
	bra.s	arp3

arp1:	moveq	#0,%d0
	move.b	0x03(%a4),%d0
	and.b	#0x0F,%d0
	bra.s	arp3

arp2:	move.w	0x10(%a4),%d2
	bra.s	arp4

arp3:	add.w	%d0,%d0
	moveq	#0,%d1
	move.w	0x10(%a4),%d1
	lea	periods(%pc),%a0
	moveq	#0x24,%d4
arploop:move.w	0(%a0,%d0.w),%d2
	cmp.w	(%a0),%d1
	bge.s	arp4
	addq.l	#2,%a0
	dbra	%d4,arploop
	rts

arp4:	move.w	%d2,0x06(%a3)
	rts

getnew:	lea	module_data+0x043C(%pc),%a0
	lea	-0x043C+0x0C(%a0),%a2
	lea	-0x043C+0x03B8(%a0),%a1

	moveq	#0,%d0
	move.l	%d0,%d1
	move.b	songpos(%pc),%d0
	move.b	0(%a1,%d0.w),%d1
	asl.l	#8,%d1
	asl.l	#2,%d1
	add.w	pattpos(%pc),%d1
	clr.w	dmacon

	lea	aud1lc(%pc),%a3
	lea	voice1(%pc),%a4
	bsr.s	playvoice
	lea	aud2lc(%pc),%a3
	lea	voice2(%pc),%a4
	bsr.s	playvoice
	lea	aud3lc(%pc),%a3
	lea	voice3(%pc),%a4
	bsr.s	playvoice
	lea	aud4lc(%pc),%a3
	lea	voice4(%pc),%a4
	bsr.s	playvoice
	bra	setdma

playvoice:	
	move.l	0(%a0,%d1.l),(%a4)
	addq.l	#4,%d1
	moveq	#0,%d2
	move.b	0x02(%a4),%d2
	and.b	#0xF0,%d2
	lsr.b	#4,%d2
	move.b	(%a4),%d0
	and.b	#0xF0,%d0
	or.b	%d0,%d2
	tst.b	%d2
	beq.s	setregs
	moveq	#0,%d3
	lea	samplestarts(%pc),%a1
	move.l	%d2,%d4
	subq.l	#0x01,%d2
	asl.l	#2,%d2
	mulu	#0x1E,%d4
	move.l	0(%a1,%d2.l),0x04(%a4)
	move.w	0(%a2,%d4.l),0x08(%a4)
	move.w	0x02(%a2,%d4.l),0x12(%a4)
	move.w	0x04(%a2,%d4.l),%d3
	tst.w	%d3
	beq.s	noloop
	move.l	0x04(%a4),%d2
	add.w	%d3,%d3
	add.l	%d3,%d2
	move.l	%d2,0x0A(%a4)
	move.w	0x04(%a2,%d4.l),%d0
	add.w	0x06(%a2,%d4.l),%d0
	move.w	%d0,8(%a4)
	move.w	0x06(%a2,%d4.l),0x0E(%a4)
	move.w	0x12(%a4),0x08(%a3)
	bra.s	setregs

noloop:	move.l	0x04(%a4),%d2
	add.l	%d3,%d2
	move.l	%d2,0x0A(%a4)
	move.w	0x06(%a2,%d4.l),0x0E(%a4)
	move.w	0x12(%a4),0x08(%a3)
setregs:move.w	(%a4),%d0
	and.w	#0x0FFF,%d0
	beq	checkcom2
	move.b	0x02(%a4),%d0
	and.b	#0x0F,%d0
	cmp.b	#0x03,%d0
	bne.s	setperiod
	bsr	setmyport
	bra	checkcom2

setperiod:	
	move.w	(%a4),0x10(%a4)
	andi.w	#0x0FFF,0x10(%a4)
	move.w	0x14(%a4),%d0
	move.w	%d0,dmactrl
	clr.b	0x1B(%a4)

	move.l	0x04(%a4),(%a3)
	move.w	0x08(%a4),0x04(%a3)
	move.w	0x10(%a4),%d0
	and.w	#0x0FFF,%d0
	move.w	%d0,0x06(%a3)
	move.w	0x14(%a4),%d0
	or.w	%d0,dmacon
	bra	checkcom2

setdma:	move.w	dmacon(%pc),%d0

	btst	#0,%d0			/*-------------------*/
	beq.s	wz_nch1			/**/
	move.l	aud1lc(%pc),wiz1lc	/**/
	moveq	#0,%d1			/**/
	moveq	#0,%d2			/**/
	move.w	aud1len(%pc),%d1	/**/
	move.w	voice1+0x0E(%pc),%d2	/**/
	add.l	%d2,%d1			/**/
	move.l	%d1,wiz1len		/**/
	move.w	%d2,wiz1rpt		/**/
	clr.w	wiz1pos			/**/

wz_nch1:btst	#1,%d0			/**/
	beq.s	wz_nch2			/**/
	move.l	aud2lc(%pc),wiz2lc	/**/
	moveq	#0,%d1			/**/
	moveq	#0,%d2			/**/
	move.w	aud2len(%pc),%d1	/**/
	move.w	voice2+0x0E(%pc),%d2	/**/
	add.l	%d2,%d1			/**/
	move.l	%d1,wiz2len		/**/
	move.w	%d2,wiz2rpt		/**/
	clr.w	wiz2pos			/**/

wz_nch2:btst	#2,%d0			/**/
	beq.s	wz_nch3			/**/
	move.l	aud3lc(%pc),wiz3lc	/**/
	moveq	#0,%d1			/**/
	moveq	#0,%d2			/**/
	move.w	aud3len(%pc),%d1	/**/
	move.w	voice3+0x0E(%pc),%d2	/**/
	add.l	%d2,%d1			/**/
	move.l	%d1,wiz3len		/**/
	move.w	%d2,wiz3rpt		/**/
	clr.w	wiz3pos			/**/

wz_nch3:btst	#3,%d0			/**/
	beq.s	wz_nch4			/**/
	move.l	aud4lc(%pc),wiz4lc	/**/
	moveq	#0,%d1			/**/
	moveq	#0,%d2			/**/
	move.w	aud4len(%pc),%d1	/**/
	move.w	voice4+0x0E(%pc),%d2	/**/
	add.l	%d2,%d1			/**/
	move.l	%d1,wiz4len		/**/
	move.w	%d2,wiz4rpt		/**/
	clr.w	wiz4pos			/*-------------------*/

wz_nch4:addi.w	#0x10,pattpos
	cmpi.w	#0x0400,pattpos
	bne.s	endr
nex:	clr.w	pattpos
	clr.b	break
	addq.b	#1,songpos
	andi.b	#0x7F,songpos
	move.b	songpos(%pc),%d1
	cmp.b	module_data+0x03B6(%pc),%d1
	bne.s	endr
	move.b	module_data+0x03B7(%pc),songpos
endr:	tst.b	break
	bne.s	nex
	rts

setmyport:	
	move.w	(%a4),%d2
	and.w	#0x0FFF,%d2
	move.w	%d2,0x18(%a4)
	move.w	0x10(%a4),%d0
	clr.b	0x16(%a4)
	cmp.w	%d0,%d2
	beq.s	clrport
	bge.s	rt
	move.b	#0x01,0x16(%a4)
	rts

clrport:clr.w	0x18(%a4)
rt:	rts

myport:	move.b	0x03(%a4),%d0
	beq.s	myslide
	move.b	%d0,0x17(%a4)
	clr.b	0x03(%a4)
myslide:tst.w	0x18(%a4)
	beq.s	rt
	moveq	#0,%d0
	move.b	0x17(%a4),%d0
	tst.b	0x16(%a4)
	bne.s	mysub
	add.w	%d0,0x10(%a4)
	move.w	0x18(%a4),%d0
	cmp.w	0x10(%a4),%d0
	bgt.s	myok
	move.w	0x18(%a4),0x10(%a4)
	clr.w	0x18(%a4)

myok:	move.w	0x10(%a4),0x06(%a3)
	rts

mysub:	sub.w	%d0,0x10(%a4)
	move.w	0x18(%a4),%d0
	cmp.w	0x10(%a4),%d0
	blt.s	myok
	move.w	0x18(%a4),0x10(%a4)
	clr.w	0x18(%a4)
	move.w	0x10(%a4),0x06(%a3)
	rts

vib:	move.b	0x03(%a4),%d0
	beq.s	vi
	move.b	%d0,0x1A(%a4)

vi:	move.b	0x1B(%a4),%d0
	lea	sin(%pc),%a1
	lsr.w	#0x02,%d0
	and.w	#0x1F,%d0
	moveq	#0,%d2
	move.b	0(%a1,%d0.w),%d2
	move.b	0x1A(%a4),%d0
	and.w	#0x0F,%d0
	mulu	%d0,%d2
	lsr.w	#0x06,%d2
	move.w	0x10(%a4),%d0
	tst.b	0x1B(%a4)
	bmi.s	vibmin
	add.w	%d2,%d0
	bra.s	vib2

vibmin:	sub.w	%d2,%d0
vib2:	move.w	%d0,0x06(%a3)
	move.b	0x1A(%a4),%d0
	lsr.w	#0x02,%d0
	and.w	#0x3C,%d0
	add.b	%d0,0x1B(%a4)
	rts

nop:	move.w	0x10(%a4),0x06(%a3)
	rts

checkcom:
.if 1     /* enabling this enables all special effects like vibrato etc */
	move.w	0x02(%a4),%d0
	and.w	#0x0FFF,%d0
	beq.s	nop
	move.b	0x02(%a4),%d0
	and.b	#0x0F,%d0
	tst.b	%d0
	beq	arpeggio
	cmp.b	#0x01,%d0
	beq.s	portup
	cmp.b	#0x02,%d0
	beq	portdown
	cmp.b	#0x03,%d0
	beq	myport
	cmp.b	#0x04,%d0
	beq	vib
	cmp.b	#0x05,%d0
	beq	port_toneslide
	cmp.b	#0x06,%d0
	beq	vib_toneslide
	move.w	0x10(%a4),0x06(%a3)
	cmp.b	#0x0A,%d0
	beq.s	volslide
.endif
	rts

volslide:	
	moveq	#0,%d0
	move.b	0x03(%a4),%d0
	lsr.b	#4,%d0
	tst.b	%d0
	beq.s	voldown
	add.w	%d0,0x12(%a4)
	cmpi.w	#0x40,0x12(%a4)
	bmi.s	vol2
	move.w	#0x40,0x12(%a4)
vol2:	move.w	0x12(%a4),0x08(%a3)
	rts

voldown:moveq	#0,%d0
	move.b	0x03(%a4),%d0
	and.b	#0x0F,%d0
	sub.w	%d0,0x12(%a4)
	bpl.s	vol3
	clr.w	0x12(%a4)
vol3:	move.w	0x12(%a4),0x08(%a3)
	rts

portup:	moveq	#0,%d0
	move.b	0x03(%a4),%d0
	sub.w	%d0,0x10(%a4)
	move.w	0x10(%a4),%d0
	and.w	#0x0FFF,%d0
	cmp.w	#0x71,%d0
	bpl.s	por2
	andi.w	#0xF000,0x10(%a4)
	ori.w	#0x71,0x10(%a4)
por2:	move.w	0x10(%a4),%d0
	and.w	#0x0FFF,%d0
	move.w	%d0,0x06(%a3)
	rts

port_toneslide:	
	bsr	myslide
	bra.s	volslide

vib_toneslide:	
	bsr	vi
	bra.s	volslide

portdown:	
	clr.w	%d0
	move.b	0x03(%a4),%d0
	add.w	%d0,0x10(%a4)
	move.w	0x10(%a4),%d0
	and.w	#0x0FFF,%d0
	cmp.w	#0x0358,%d0
	bmi.s	por3
	andi.w	#0xF000,0x10(%a4)
	ori.w	#0x0358,0x10(%a4)
por3:	move.w	0x10(%a4),%d0
	and.w	#0x0FFF,%d0
	move.w	%d0,0x06(%a3)
	rts

checkcom2:	
	move.b	0x02(%a4),%d0
	and.b	#0x0F,%d0
	cmp.b	#0x0D,%d0
	beq.s	pattbreak
	cmp.b	#0x0B,%d0
	beq.s	posjmp
	cmp.b	#0x0C,%d0
	beq.s	setvol
	cmp.b	#0x0F,%d0
	beq.s	setspeed
	rts

pattbreak:	
	st	break
	rts

posjmp:	move.b	0x03(%a4),%d0
	subq.b	#0x01,%d0
	move.b	%d0,songpos
	st	break
	rts

setvol:	moveq	#0,%d0
	move.b	0x03(%a4),%d0
	cmp.w	#0x40,%d0
	ble.s	vol4
	move.b	#0x40,0x03(%a4)
vol4:	move.b	0x03(%a4),0x09(%a3)
	move.b	0x03(%a4),0x13(%a4)
	rts

setspeed:	
	cmpi.b	#0x1F,0x03(%a4)
	ble.s	sets
	move.b	#0x1F,0x03(%a4)
sets:	move.b	0x03(%a4),%d0
	beq.s	rts2
	move.w	%d0,speed
	clr.w	counter
rts2:	rts

sin:	DC.B 0x00,0x18,0x31,0x4A,0x61,0x78,0x8D,0xA1,0xB4,0xC5,0xD4,0xE0,0xEB,0xF4,0xFA,0xFD
	DC.B 0xFF,0xFD,0xFA,0xF4,0xEB,0xE0,0xD4,0xC5,0xB4,0xA1,0x8D,0x78,0x61,0x4A,0x31,0x18

periods:DC.W 0x0358,0x0328,0x02FA,0x02D0,0x02A6,0x0280,0x025C,0x023A,0x021A,0x01FC,0x01E0
	DC.W 0x01C5,0x01AC,0x0194,0x017D,0x0168,0x0153,0x0140,0x012E,0x011D,0x010D,0xFE
	DC.W 0xF0,0xE2,0xD6,0xCA,0xBE,0xB4,0xAA,0xA0,0x97,0x8F,0x87
	DC.W 0x7F,0x78,0x71,0x00,0x00

speed:	DC.W 0x06
counter:DC.W 0x00
songpos:DC.B 0x00
break:	DC.B 0x00
pattpos:DC.W 0x00

dmacon:	DC.W 0x00
samplestarts:	DS.L 0x1F

voice1:	DS.W 10
	DC.W 0x01
	DS.W 3
voice2:	DS.W 10
	DC.W 0x02
	DS.W 3
voice3:	DS.W 10
	DC.W 0x04
	DS.W 3
voice4:	DS.W 10
	DC.W 0x08
	DS.W 3

.globl module_data
module_data:
	/* include the mod file itself */
	.include "../axel_f.mod.s"
	DS.l	16384*4			/* Workspace*/
workspc:	DS.W	1
