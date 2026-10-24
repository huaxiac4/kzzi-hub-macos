import sys, json, time
from kzzi import KZZI, hexs, REPORT_ID, CMD_WRITE, CMD_SAVE

frags = [bytearray(int(x,16) for x in h.split()) for h in json.load(open('cfg_backup.json'))]
print("read-back frag0:", hexs(frags[0]))

# identity write: cmd 0x04, keep data, set confirm flag frame[8]=1, apply frame[14]=0
for i,f in enumerate(frags):
    f[1] = CMD_WRITE
frags[0][8] = 0x01
frags[0][14] = 0x00

k = KZZI()
try:
    print("ping:", hexs(k.ping()[0]))
    for i,f in enumerate(frags):
        frame = bytearray(f); frame[19] = 0
        frame[19] = sum(frame[:19]) & 0xff
        k._tx(frame[1:])
        rx = k._drain(120)
        print("wr", i, "->", [hexs(x) for x in rx])
    print("save:", [hexs(x) for x in k.save()])
    time.sleep(0.3)
    back = k.read_cfg()
    print("read back:", len(back))
    for b in back: print("  ", hexs(b))
finally:
    k.close()
