.section .text
.globl _start

_start:
    addi x1, x0, 20
    andi x2, x1, 12
    ori  x3, x1, 5
    xori x4, x1, 7
    slti x5, x1, 25
    slli x6, x1, 2
    srli x7, x6, 2
    srai x8, x6, 2

loop:
    jal x0, loop
