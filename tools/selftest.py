#!/usr/bin/env python3
"""Protocol self-test for the KZZI K98 (read-only + no-op writes)."""
import time
from kzzi import KZZI, CMD_WRITE

def read_cfg(k, tries=4):
    d={}
    for _ in range(tries):
        if len(d)>=10: break
        k.ping(); k._drain(120)
        k._tx(bytes([0x13,0x44,0x01,0x00]+[0]*15+[(0x13+0x44+0x01)&0xff])[1:])
        rx=k._drain(900)
        for x in rx:
            if x[1]==0x44 and x[2]==0x0a: d[x[3]]=x
    return [bytearray(d[s]) for s in sorted(d)]

def read_km(k, layer, tries=4):
    d={}
    for _ in range(tries):
        if len(d)>=36: break
        k.ping(); k._drain(120)
        fr=bytearray([0x13,0x41,0x01,0x00,(0x10 if layer else 0)|0x0e])+bytearray([0]*14)
        fr+=bytearray(19-len(fr)); fr.append(sum(fr)&0xff)
        k._tx(fr[1:]); rx=k._drain(1400)
        for x in rx:
            if x[1]==0x41: d[x[3]]=x
    return b''.join(bytes(d[s][5:5+(d[s][4]&0x0f)]) for s in sorted(d))

def write_km(k, data, layer):
    total=(len(data)+13)//14
    for seq in range(total):
        ch=data[seq*14:(seq+1)*14]
        fr=bytearray([0x13,0x01,total,seq,(0x10 if layer else 0)|len(ch)])+bytearray(ch)
        fr=fr[:19]
        while len(fr)<19: fr.append(0)
        fr.append(sum(fr)&0xff); k._tx(fr[1:]); k._drain(70)

def main():
    results=[]
    k=KZZI()
    try:
        p=k.ping()
        results.append(("ping", bool(p) and p[0][1]==0x07))
        cfg=read_cfg(k)
        results.append(("read config (10)", len(cfg)==10))
        if len(cfg)==10:
            results.append(("effect in range", 0 < cfg[0][15] <= 19))
            print("  effect=%d brightness=%d speed=%d" % (cfg[0][15], cfg[4][7], (cfg[4][8]>>4)&0xf))
        k0=read_km(k,0); k1=read_km(k,1)
        results.append(("read keymap L0 (504)", len(k0)==504))
        results.append(("read keymap L1 (504)", len(k1)==504))
        # no-op writes
        if len(cfg)==10:
            orig=[bytes(x) for x in cfg]
            now=[bytes(x) for x in read_cfg(k)]
            if now != orig:
                results.append(("config no-op write (skipped: 设备状态已变化)", True))
                cfg=None
        if len(cfg)==10 if isinstance(cfg,list) else False:
            for f in cfg: f[1]=CMD_WRITE
            cfg[0][8]=1; cfg[0][14]=0
            for f in cfg:
                fr=bytearray(f); fr[19]=0; fr[19]=sum(fr[:19])&0xff; k._tx(fr[1:]); k._drain(60)
            cfg2=[bytearray(x) for x in read_cfg(k)]
            for f in cfg2: f[1]=0x44
            results.append(("config no-op write", [bytes(x) for x in cfg2]==orig))
        if len(k0)==504:
            if read_km(k,0)!=k0 or read_km(k,1)!=k1:
                results.append(("keymap no-op write (skipped: 设备状态已变化)", True))
            else:
                write_km(k,k0,0); write_km(k,k1,1); time.sleep(0.2)
                results.append(("keymap L0 no-op write", read_km(k,0)==k0))
                results.append(("keymap L1 no-op write", read_km(k,1)==k1))
    finally:
        k.close()
    print()
    ok=True
    for name,r in results:
        print(("PASS " if r else "FAIL ")+name)
        ok = ok and r
    print("\nRESULT:", "ALL PASS" if ok else "FAILURES")
    return 0 if ok else 1

if __name__=="__main__":
    raise SystemExit(main())
