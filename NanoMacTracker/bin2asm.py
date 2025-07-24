#!/usr/bin/python3
import sys

if len(sys.argv) != 2:
    print("Usage: bin2asm <file>")
else:
    with open(sys.argv[1], 'rb') as f:
        bin = f.read()

        for i in range(len(bin)):        
            if i % 16 == 0: print("\tdc.b\t", end="")
            print("0x{:02x}".format(bin[i]), end="")
            if i % 16 != 15 and i != len(bin)-1: print(", ", end="")
            else: print()
                
        f.close()
