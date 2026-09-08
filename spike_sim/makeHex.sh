# Assembly → object
riscv64-unknown-elf-as -march=rv32im -mabi=ilp32 test.S -o test.o

# Object → raw .text binary
riscv64-unknown-elf-objcopy -O binary -j .text test.o test.bin

# Binary → RTL hex
python3 binToHex.py
