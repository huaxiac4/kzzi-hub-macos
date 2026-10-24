#!/usr/bin/env python3
"""KZZI K98 (2.4G dongle) protocol helper - drives ./hidbridge over stdio."""
import subprocess, sys, time, os, json, re

REPORT_ID = 0x13
CMD_READ = 0x44
CMD_WRITE = 0x04
CMD_SAVE = 0x0A
CMD_PALETTE = 0x09
CMD_PERKEY = 0x02
CMD_PING = 0x07
CMD_MUSIC = 0x88

HERE = os.path.dirname(os.path.abspath(__file__))


class KZZI:
    def __init__(self, bridge=os.path.join(HERE, "hidbridge")):
        self.p = subprocess.Popen([bridge], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, bufsize=1)
        line = self.p.stdout.readline().strip()
        if line != "OK":
            raise RuntimeError("bridge failed: %r %s" % (line, self.p.stderr.read()))

    def close(self):
        try:
            self.p.stdin.write("QUIT\n"); self.p.stdin.flush()
            self.p.wait(timeout=2)
        except Exception:
            self.p.kill()

    def _tx(self, payload19):
        """payload19 = 19 bytes (cmd..checksum), report id prepended."""
        data = bytes([REPORT_ID]) + bytes(payload19)
        assert len(data) == 20
        self.p.stdin.write("TX " + " ".join("%02x" % b for b in data) + "\n")
        self.p.stdin.flush()
        line = self.p.stdout.readline().strip()
        if not line.startswith("TXOK"):
            raise RuntimeError("tx failed: " + line)

    def _drain(self, ms=250):
        self.p.stdin.write("RX %d\n" % ms)
        self.p.stdin.flush()
        out = []
        while True:
            line = self.p.stdout.readline()
            if not line:
                break
            line = line.strip()
            if line == "END":
                break
            if line.startswith("RX "):
                parts = line.split()
                out.append(bytes(int(x, 16) for x in parts[2:]))
        return out

    @staticmethod
    def packet(cmd, sub, seq, data=b""):
        b = bytearray(19)
        b[0] = cmd
        b[1] = sub
        b[2] = seq
        b[3] = len(data)
        b[4:4 + len(data)] = data
        total = (REPORT_ID + sum(b[:4 + len(data)])) & 0xff
        # checksum over the full 20-byte frame (report id included) must be 0
        # frame = [0x13, cmd, sub, seq, len, data..., pad..., checksum]
        frame = bytearray([REPORT_ID, cmd, sub, seq, len(data)]) + bytearray(data)
        frame += bytearray(19 - len(frame))
        frame.append(sum(frame) & 0xff)
        return bytes(frame[1:])

    def cmd(self, cmd, sub=0x01, seq=0, data=b"", wait=250):
        self._tx(self.packet(cmd, sub, seq, data))
        return self._drain(wait)

    def ping(self):
        return self.cmd(CMD_PING, 0x01, 0, b"\x00", 200)

    def read_cfg(self, wait=600):
        frags = self.cmd(CMD_READ, 0x01, 0, b"\x00" * 14, wait)
        # keep only config fragments
        cfg = [f for f in frags if len(f) >= 20 and f[0] == REPORT_ID and f[1] == CMD_READ and f[2] == 0x0A]
        return cfg

    def write_cfg(self, frags, gap=60):
        echoes = []
        for i, f in enumerate(frags):
            p = bytearray(f[1:])  # strip report id
            p[0] = CMD_WRITE
            p[19 - 1] = 0  # recompute below
            frame = bytearray([REPORT_ID]) + p
            frame[-1] = 0
            frame[-1] = sum(frame[:-1]) & 0xff
            self._tx(frame[1:])
            echoes.extend(self._drain(gap))
        return echoes

    def save(self, wait=400):
        # 13 0A 01 00 04 07 00 ...
        data = bytes([0x04, 0x07] + [0] * 12)
        return self.cmd(CMD_SAVE, 0x01, 0, data, wait)


def hexs(b):
    return " ".join("%02x" % x for x in b)


def main():
    k = KZZI()
    try:
        if len(sys.argv) < 2 or sys.argv[1] == "read":
            print("ping:", [hexs(f) for f in k.ping()])
            frags = k.read_cfg()
            print("config fragments:", len(frags))
            for f in frags:
                print(" ", hexs(f))
            with open(os.path.join(HERE, "cfg_backup.json"), "w") as fh:
                json.dump([hexs(f) for f in frags], fh, indent=1)
            print("saved cfg_backup.json")
    finally:
        k.close()


if __name__ == "__main__":
    main()
