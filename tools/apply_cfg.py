import sys, json, time
from kzzi import KZZI, hexs, CMD_WRITE
# usage: apply_cfg.py <seq> <off> <value> [<seq2> <off2> <val2> ...]  (no save unless --save)
mods = []
args = sys.argv[1:]
save = '--save' in args
args = [a for a in args if a != '--save']
for i in range(0, len(args), 3):
    mods.append((int(args[i]), int(args[i+1]), int(args[i+2], 16)))
frags = [bytearray(int(x,16) for x in h.split()) for h in json.load(open('cfg_backup.json'))]
# use the latest read as base
frags = [bytearray(int(x,16) for x in h.split()) for h in json.load(open('cfg_latest.json'))]
for i,f in enumerate(frags): f[1] = CMD_WRITE
frags[0][8] = 0x01
frags[0][14] = 0x00
for s,o,v in mods:
    print("frag%d[%d]: %02x -> %02x" % (s,o,frags[s][o],v)); frags[s][o]=v
k = KZZI()
try:
    k.ping(); time.sleep(0.05)
    for i,f in enumerate(frags):
        frame = bytearray(f); frame[19]=0; frame[19]=sum(frame[:19])&0xff
        k._tx(frame[1:])
        rx = k._drain(200)
        if i==0 or i==9 or not rx: print("wr%d echo: %s" % (i, [hexs(x) for x in rx]))
        time.sleep(0.03)
    if save:
        print("save:", [hexs(x) for x in k.save(700)])
        time.sleep(0.4)
    k.ping()
    cfgs=[f for f in k.read_cfg(800) if f[2]==0x0a]
    # dedupe by seq
    d={}
    for f in cfgs: d[f[3]]=f
    out=[d[s] for s in sorted(d)]
    for f in out: print("  ", hexs(f))
    json.dump([hexs(f) for f in out], open('cfg_latest.json','w'), indent=1)
finally:
    k.close()
