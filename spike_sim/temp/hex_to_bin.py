#!/usr/bin/env python3
"""Convert a $readmemh-style hex file (one 32-bit word per line, optional
CRLF/comments/blank lines) into a little-endian flat binary.

Matches the format produced by tb/hex/gen_hex.py and riscv_enc.py-based
generators: one 8-hex-digit word per line, MSB-first text, no address
column.

Usage:
    python hex_to_bin.py program.hex program.bin
    python hex_to_bin.py program.hex program.bin --trim-trailing-nops
"""
import sys
import struct
import argparse

NOP = 0x00000013


def parse_hex_words(path):
    words = []
    with open(path, "r") as f:
        for line in f:
            line = line.split("//")[0].strip()  # strip comments/CRLF
            if not line:
                continue
            words.append(int(line, 16) & 0xFFFFFFFF)
    return words


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hex_in")
    ap.add_argument("bin_out")
    ap.add_argument("--trim-trailing-nops", action="store_true",
                     help="Drop trailing NOP-padding words (shrinks the ELF; "
                          "not required, spike doesn't care about padding)")
    args = ap.parse_args()

    words = parse_hex_words(args.hex_in)

    if args.trim_trailing_nops:
        while words and words[-1] == NOP:
            words.pop()

    with open(args.bin_out, "wb") as f:
        for w in words:
            f.write(struct.pack("<I", w))  # little-endian, matches RISC-V

    print(f"{args.hex_in}: {len(words)} words -> {args.bin_out} "
          f"({len(words)*4} bytes)")


if __name__ == "__main__":
    main()
