import struct
import sys

print(f"Python Version: {sys.version}")
print(f"Struct size <4sI: {struct.calcsize('<4sI')}")

try:
    wav_header = bytearray(44)
    struct.pack_into("<4sI", wav_header, 36, b"data", 0)
    print("✅ struct.pack_into successful")
except Exception as e:
    print(f"❌ struct.pack_into failed: {e}")

try:
    wav_header = bytearray(44)
    # Simulate if I was Q
    struct.pack_into("<4sQ", wav_header, 36, b"data", 0)
    print("✅ struct.pack_into (Q) successful")
except Exception as e:
    print(f"❌ struct.pack_into (Q) failed: {e}")
