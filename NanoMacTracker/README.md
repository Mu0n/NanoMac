# NanoMacTracker - MOD tracker audio player for classic Macs

When working on the NanoMac I was surprised to find that there is no
MOD tracker sound file player for the first classic 68k Macintosh
computers. The MOD file format was created for the Commodore Amiga and
relates closely to its audio capabilities. Various playback routine
variants were later written for the Atari ST as well. Both, the Amiga
and the Atari ST were ~8Mhz 68000 based machines and were very similar
to the first Apple Macintoshs with its 7+ Mhz 68000 CPU and the 22kHz
single channel PCM audio capabilities making it the perfect target for
this.

Following up on a discussion about
[MOD replay routines at Atari-Forum](https://www.atari-forum.com/viewtopic.php?t=43127)
I took the so-called Wizzcat routine and started to port it to the
Apple Macintosh. With some modifications that routine can be assembled
using the gas assembler from the [Retro68 environment](https://github.com/autc04/Retro68).
This can be used to compile and I was able to run the code on [MiniVMac](https://minivmac.github.io/gryphel-mirror/c/minivmac/)
and in the [NanoMac](https://github.com/harbaum/NanoMac) as seen in [this Youtube video](https://www.youtube.com/shorts/FYBnCcJiEAo).
It reportedly also runs on [genuine hardware](https://68kmla.org/bb/index.php?threads/modtracker-audio-replay-on-early-68k-macs.50519/#post-568500).

## Running it yourself

A disk image containing an early test version can be found [here](https://68kmla.org/bb/index.php?threads/modtracker-audio-replay-on-early-68k-macs.50519/#post-568475).

## Building it

This was made using the [Retro68 environment](https://github.com/autc04/Retro68). To compiled it just clone
the NanoMac repository and invoke Retro68 like so:

```
$ git clone https://github.com/harbaum/NanoMac.git
$ cd NanoMac/NanoMacTracker
```

The you need to add the MOD track to include for playback. I included a python script to convert the
binary file into the assembler source code.

```
$ ./bin2asm.py axel_f.mod > axel_f.mod.s
```

A matching MOD file can e.g. be found [here](https://modarchive.org/index.php?request=view_by_moduleid&query=32394)

With all files in place now, the build itself can be prepared and started.

```
$ mkdir build
$ cd build
$ cmake .. -DCMAKE_TOOLCHAIN_FILE=/opt/Retro68/Retro68-build/toolchain/m68k-apple-macos/cmake/retro68.toolchain.cmake
...
$ make 
[ 20%] Building C object CMakeFiles/NanoMacTracker.dir/nanomactracker.c.obj
[ 40%] Building C object CMakeFiles/NanoMacTracker.dir/font_16x8.c.obj
[ 60%] Building ASM object CMakeFiles/NanoMacTracker.dir/wc_mod.s.obj
[ 80%] Linking C executable NanoMacTracker.code.bin
[ 80%] Built target NanoMacTracker
[100%] Generating NanoMacTracker.bin, NanoMacTracker.APPL, NanoMacTracker.dsk, NanoMacTracker.ad, %NanoMacTracker.ad
[100%] Built target NanoMacTracker_APPL
```

This will give you several variants of the NanoMacTracker including a floppy disk image.

## How it works

There are two tasks the player needs to do. It has to keep the Macs
audio replay buffer updated with fresh audio data. Since this buffer
is 370 bytes in length and is played synchronous to the Macs video
output it needs to be updated exactly once per frame, preferrably in
the VBL interrupt at 60Hz. The second thing that needs to happen is
that the tunes to be played have to be recalculated every 20ms. This
should thus happen at 50Hz.

The entore playback takes place inside the VBL interrupt and takes
up around 80% of the available CPU time leaving less than 20% for
the main task doing e.g. a user interface.

Since this replaces the Macs own VBL handler routine and disables
all other interrupts, MacOS basically stops working while the
player is running.

## Current state and things to do

The current state is:
  - The player is playing many MODs with minor clicks and noises
  - Some MODs play with significant artifacts
  - Some MODs make the player crash

Things that should be worked on:
  - Clicks, noises and major artifacts. The reason for this is not
    clear and needs investigation
  - Crashes. These seem to happen during the preparation state and
    might be causes by a stack overflow as that stage seeems to
    require siognificant stack space
  - Optimizations
    - The current version mixes the two signed 8 bit audio channels
      as computed for the STE. Adopting the sample preparation to
      unsigned 7 bit can simplify the mixing during playback
    - The Macs hardware supports some audio double buffering using
      the alternate audio buffer. This may be used to directly
      render the samples into the hardware audio buffers allowing
      to entirely omit the final copying stage and further reducing
      the CPU load


