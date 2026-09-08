.section .text
.globl _start

_start:
    addi x1, x0, 15
    addi x2, x0, 2
    sll  x3, x1, x2
    srl  x4, x3, x2
    sra  x5, x3, x2

loop:
    jal x0, loop
