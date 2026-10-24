import json, time
from kzzi import KZZI, hexs

def read_keymap(k):
    k._drain(200)
    fr=bytearray([0x13,0x41,0x01,0x00,0x0e])+bytearray([0]*14)
    fr+=bytearray(19-len(fr)); fr.append(sum(fr)&0xff)
    k._tx(fr[1:]); rx=k._drain(1500)
    d={}
    for x in rx:
        if x[1]==0x41: d[x[3]]=x
    if len(d)<36: raise RuntimeError("short keymap %d"%len(d))
    return b''.join(bytes(d[s][5:5+d[s][4]]) for s in sorted(d))

def write_keymap(k, data, total=36):
    echoed=0
    for seq in range(total):
        chunk=data[seq*14:(seq+1)*14]
        fr=bytearray([0x13,0x01,total,seq,0x0e])+bytearray(chunk)
        fr=fr[:19]; 
        while len(fr)<19: fr.append(0)
        fr.append(sum(fr)&0xff)
        k._tx(fr[1:]); rx=k._drain(120)
        if rx: echoed+=1
    return echoed

k=KZZI()
try:
    k.ping()
    km=read_keymap(k)
    print("read", len(km), "first rec:", hexs(km[0:4]))
    json.dump(hexs(km), open('keymap_backup.json','w'))
    mod=bytearray(km); old=mod[3]; mod[3]=0x04
    print("modify rec0 code %02x -> 04"%old)
    print("echoed:", write_keymap(k, bytes(mod)))
    time.sleep(0.4)
    back=read_keymap(k)
    print("readback rec0:", hexs(back[0:4]), "match:", back[0:4]==bytes(mod[0:4]))
    # restore
    print("restore echoed:", write_keymap(k, km))
    time.sleep(0.4)
    back2=read_keymap(k)
    print("restored rec0:", hexs(back2[0:4]), "ok:", back2[0:4]==km[0:4])
finally:
    k.close()
