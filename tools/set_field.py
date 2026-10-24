import sys, json, time
from kzzi import KZZI, hexs, CMD_WRITE

# usage: set_field.py <seq> <offset> <value_hex> [save]
seq, off, val = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3], 16)
do_save = len(sys.argv) > 4 and sys.argv[4] == 'save'
frags = [bytearray(int(x,16) for x in h.split()) for h in json.load(open('cfg_backup.json'))]
for i,f in enumerate(frags): f[1] = CMD_WRITE
frags[0][8] = 0x01; frags[0][14] = 0x00
old = frags[seq][off]
frags[seq][off] = val
print("seq %d off %d: %02x -> %02x" % (seq, off, old, val))
k = KZZI()
try:
    k.ping()
    for i,f in enumerate(frags):
        frame = bytearray(f); frame[19] = 0; frame[19] = sum(frame[:19]) & 0xff
        k._tx(frame[1:]); rx = k._drain(90)
        if i == seq: print(" echo:", [hexs(x) for x in rx])
    if do_save: print(" save:", [hexs(x) for x in k.save(500)])
finally:
    k.close()
