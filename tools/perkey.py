import json, time
from kzzi import KZZI, hexs, CMD_WRITE, CMD_PERKEY

def build_planes(assign):
    """assign: dict led_index -> (r,g,b)"""
    planes = [[0]*126 for _ in range(3)]
    for idx,(r,g,b) in assign.items():
        if 0 <= idx < 126:
            planes[0][idx]=r; planes[1][idx]=g; planes[2][idx]=b
    return planes

def write_perkey(k, assign, gap=60):
    planes = build_planes(assign)
    for seq in range(27):
        p = seq // 9; f = seq % 9
        vals = planes[p][f*14:(f+1)*14]
        data = bytes(vals)
        frame = bytearray([0x13, CMD_PERKEY, 0x1C, seq, len(data)]) + bytearray(data)
        frame += bytearray(19-len(frame)); frame.append(sum(frame)&0xff)
        k._tx(frame[1:]); k._drain(gap)
    trailer = bytes([0x06,0,0,0x5A,0xA5,0,0,0,0,0,0,0,0,0])
    frame = bytearray([0x13, CMD_PERKEY, 0x1C, 27, len(trailer)]) + bytearray(trailer)
    frame += bytearray(19-len(frame)); frame.append(sum(frame)&0xff)
    k._tx(frame[1:]); k._drain(gap)

if __name__ == "__main__":
    frags = [bytearray(int(x,16) for x in h.split()) for h in json.load(open('cfg_latest.json'))]
    for f in frags: f[1]=CMD_WRITE
    frags[0][8]=0x01; frags[0][14]=0x00
    frags[0][15]=19      # self-define / per-key
    frags[0][17]=0x01
    frags[4][7]=5        # brightness max
    frags[4][8]=0x00     # no speed, single color mode
    k = KZZI()
    try:
        k.ping()
        write_perkey(k, {0:(255,0,0), 1:(0,255,0), 2:(0,0,255), 35:(255,0,255)})
        for i,f in enumerate(frags):
            frame=bytearray(f); frame[19]=0; frame[19]=sum(frame[:19])&0xff
            k._tx(frame[1:]); k._drain(80)
        print("save:", [hexs(x) for x in k.save(600)])
        time.sleep(0.3)
        cfgs={}
        for f in k.read_cfg(800):
            if f[2]==0x0a: cfgs[f[3]]=f
        print("frag0 after:", hexs(cfgs[0]) if 0 in cfgs else "?")
    finally:
        k.close()
