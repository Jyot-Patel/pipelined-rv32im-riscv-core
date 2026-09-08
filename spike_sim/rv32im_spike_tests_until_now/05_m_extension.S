.section .text
.option arch, rv32im
.globl _start

_start:
    addi x1,  x0, 10
    addi x2,  x0, 20
    addi x3,  x0, -10
    addi x4,  x0, -5
    addi x5,  x0, 7
    addi x6,  x0, 12
    addi x7,  x0, 3
    addi x8,  x0, 0
    addi x9,  x0, -1
    lui  x10, 0x80000
    nop
    nop
    nop
    nop

    mul   x13, x1, x2
    nop
    nop
    nop
    nop
    mul   x14, x3, x2
    nop
    nop
    nop
    nop

    mulh  x15, x1, x2
    nop
    nop
    nop
    nop
    mulh  x16, x3, x2
    nop
    nop
    nop
    nop
    mulh  x17, x10, x10
    nop
    nop
    nop
    nop

    mulhsu x18, x1, x9
    nop
    nop
    nop
    nop
    mulhsu x19, x3, x2
    nop
    nop
    nop
    nop

    mulhu x20, x1, x2
    nop
    nop
    nop
    nop
    mulhu x21, x9, x9
    nop
    nop
    nop
    nop

    div   x22, x2, x1
    nop
    nop
    nop
    nop
    div   x23, x3, x5
    nop
    nop
    nop
    nop
    div   x24, x10, x9
    nop
    nop
    nop
    nop
    div   x25, x1, x8
    nop
    nop
    nop
    nop

    divu  x26, x2, x5
    nop
    nop
    nop
    nop
    divu  x27, x2, x8
    nop
    nop
    nop
    nop

    rem   x28, x2, x1
    nop
    nop
    nop
    nop
    rem   x29, x3, x5
    nop
    nop
    nop
    nop
    rem   x30, x1, x8
    nop
    nop
    nop
    nop
    rem   x31, x10, x9
    nop
    nop
    nop
    nop

    remu  x11, x2, x5
    nop
    nop
    nop
    nop
    remu  x12, x2, x8
    nop
    nop
    nop
    nop

    addi x6, x0, 6
    nop
    nop
    nop
    nop
    mul  x11, x6, x5
    addi x11, x11, 1
    nop
    nop
    nop
    nop

    addi x3, x0, 2
    addi x4, x0, 3
    addi x5, x0, 4
    addi x6, x0, 5
    nop
    nop
    nop
    nop
    mul x11, x3, x4
    mul x12, x5, x6
    nop
    nop
    nop
    nop

halt:
    j halt
