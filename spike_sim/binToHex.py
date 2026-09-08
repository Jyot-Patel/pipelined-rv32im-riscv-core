import struct

with open("test.bin", "rb") as f:
    data = f.read()

with open("program.hex", "w") as f:
    for i in range(0, len(data), 4):
        word = struct.unpack("<I", data[i:i+4])[0]
        f.write(f"{word:08x}\n")
