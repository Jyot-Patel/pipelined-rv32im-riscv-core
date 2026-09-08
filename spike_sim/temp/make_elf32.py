            #!/usr/bin/env python3
"""Wrap raw binaries into a minimal ELF32 RISC-V executable that Spike's
fesvr loader can run directly -- no riscv-gnu-toolchain / linker needed.

Spike's elf loader only needs a valid ELF header + PT_LOAD program headers;
it does not require section headers or a symbol table (tohost/fromhost are
optional -- if absent, spike just runs until you stop it, e.g. via `timeout`).

Usage:
    python make_elf32.py program.bin out.elf --entry 0x0
    python make_elf32.py program.bin out.elf --entry 0x0 \
        --data data.bin --data-base 0x1000

Layout convention (matches the RTL's instr_mem/data_mem masked-index fix):
    .text  @ 0x00000000  (instructions, entry point)
    .data  @ 0x00001000  (data segment, default -- override with --data-base)
"""
import argparse
import struct

EM_RISCV = 243
ET_EXEC = 2
ELFCLASS32 = 1
ELFDATA2LSB = 1
PT_LOAD = 1
PF_X, PF_W, PF_R = 1, 2, 4


def build_elf(segments, entry):
    """Build a minimal ELF32 RISC-V executable accepted by Spike."""

    n = len(segments)

    # ELF32 header and program-header sizes
    ehsize = 52
    phentsize = 32
    phoff = ehsize

    # We provide one NULL section header.
    shentsize = 40
    shnum = 1
    shstrndx = 0

    # Program data starts after ELF + program headers,
    # aligned to 0x1000.
    data_start = phoff + phentsize * n
    data_start = (data_start + 0xFFF) & ~0xFFF

    offsets = []
    off = data_start

    for _, data, _ in segments:
        # Keep PT_LOAD file offsets page aligned.
        off = (off + 0xFFF) & ~0xFFF
        offsets.append(off)
        off += len(data)

    # Section-header table goes after all segment data.
    shoff = (off + 0xFFF) & ~0xFFF

    e_ident = bytes([
        0x7F, ord('E'), ord('L'), ord('F'),
        ELFCLASS32, ELFDATA2LSB, 1, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    ])

    ehdr = struct.pack(
        "<16sHHIIIIIHHHHHH",
        e_ident,
        ET_EXEC,       # e_type
        EM_RISCV,      # e_machine
        1,              # e_version
        entry,          # e_entry
        phoff,          # e_phoff
        shoff,          # e_shoff
        0,              # e_flags
        ehsize,         # e_ehsize
        phentsize,      # e_phentsize
        n,              # e_phnum
        shentsize,      # e_shentsize
        shnum,          # e_shnum
        shstrndx,       # e_shstrndx
    )

    phdrs = b""

    for (vaddr, data, flags), foff in zip(segments, offsets):
        phdrs += struct.pack(
            "<IIIIIIII",
            PT_LOAD,
            foff,          # p_offset
            vaddr,         # p_vaddr
            vaddr,         # p_paddr
            len(data),     # p_filesz
            len(data),     # p_memsz
            flags,         # p_flags
            0x1000,        # p_align
        )

    # Build file up to the first segment.
    body = bytearray(ehdr + phdrs)

    # Pad to first segment offset.
    if len(body) < offsets[0]:
        body.extend(b'\x00' * (offsets[0] - len(body)))

    # Add each segment at its specified file offset.
    for (_, data, _), foff in zip(segments, offsets):
        if len(body) < foff:
            body.extend(b'\x00' * (foff - len(body)))
        body.extend(data)

    # Pad to section-header table.
    if len(body) < shoff:
        body.extend(b'\x00' * (shoff - len(body)))

    # One NULL section header.
    body.extend(b'\x00' * shentsize)

    return bytes(body)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text_bin")
    ap.add_argument("elf_out")
    ap.add_argument("--entry", default="0x0")
    ap.add_argument("--text-base", default="0x0")
    ap.add_argument("--data", default=None, help="optional data.bin")
    ap.add_argument("--data-base", default="0x1000")
    args = ap.parse_args()

    with open(args.text_bin, "rb") as f:
        text = f.read()

    segments = [(int(args.text_base, 0), text, PF_R | PF_W | PF_X)]

    if args.data:
        with open(args.data, "rb") as f:
            data = f.read()
        segments.append((int(args.data_base, 0), data, PF_R | PF_W))

    elf = build_elf(segments, int(args.entry, 0))
    with open(args.elf_out, "wb") as f:
        f.write(elf)

    print(f"Wrote {args.elf_out}: entry=0x{int(args.entry,0):x}, "
          f"{len(segments)} segment(s)")
    for (vaddr, data, _) in segments:
        print(f"  @0x{vaddr:08x}  {len(data)} bytes")


if __name__ == "__main__":
    main()
