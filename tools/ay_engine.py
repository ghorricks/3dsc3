"""AY engine shared by the tune generators (extracted from storm.py): midi/period/parse, per-frame states -> registers, PSG writer, WAV renderer."""
import math, numpy as np
from scipy.signal import resample_poly, butter, sosfilt
from scipy.io import wavfile
CLOCK = 1773400
FPS = 50
NOTE = {'C':0,'C#':1,'D':2,'D#':3,'E':4,'F':5,'F#':6,'G':7,'G#':8,'A':9,'A#':10,'B':11}
def midi(n):
    name, octv = n[:-1], int(n[-1])
    return 12*(octv+1) + NOTE[name]
def period(m):
    f = 440*2**((m-69)/12)
    return max(1, min(4095, round(CLOCK/(16*f))))
def parse(s):
    out = []
    for tok in s.split():
        n, l = tok.split(':')
        fl = ''.join(c for c in l if c.isalpha()); l = int(''.join(c for c in l if c.isdigit()))
        out.append((None if n == 'r' else midi(n), l, fl))
    return out
def states_to_regs(frames):
    regs = []
    for st in frames:
        r = [0]*14; mixer = 0x3F
        for i, c in enumerate('ABC'):
            tp, vol, tone, noise = st[c]
            r[i*2] = tp & 0xFF; r[i*2+1] = (tp >> 8) & 0x0F; r[8+i] = min(15, vol)
            if tone: mixer &= ~(1 << i)
            if noise: mixer &= ~(1 << (i+3))
        r[7] = mixer; r[6] = st['noise'] if st.get('noise') else 1
        regs.append((r, None))
    return regs
def write_psg(regs, path):
    with open(path, 'wb') as fp:
        fp.write(b'PSG\x1a' + bytes([0x10, FPS]) + bytes(10))
        last = [None]*14
        for r, trig in regs:
            fp.write(b'\xff')
            for i in range(13):
                if r[i] != last[i]: fp.write(bytes([i, r[i]])); last[i] = r[i]
            if trig is not None: fp.write(bytes([13, trig]))
        fp.write(b'\xfd')
def render(regs_per_frame, path):
    # ---------------------------------------------------------------- AY emulation
    SR = 44100
    OS = 4
    SRO = SR*OS
    N = SRO // FPS
    VOL = np.array([0, 0.0137, 0.0205, 0.0291, 0.0423, 0.0618, 0.0847, 0.1369,
                    0.1691, 0.2647, 0.3527, 0.4499, 0.5704, 0.6873, 0.8482, 1.0])
    # 17-bit LFSR noise
    lfsr, bits = 1, np.zeros(131071, dtype=np.uint8)
    for i in range(131071):
        bits[i] = lfsr & 1
        lfsr = (lfsr >> 1) | (((lfsr ^ (lfsr >> 3)) & 1) << 16)
    
    def env_levels(pos, shape):
        """pos: float array of envelope step index since trigger (16 steps per ramp)."""
        k = np.floor(pos).astype(np.int64)
        ramp, step = k // 16, k % 16
        att = bool(shape & 4)
        if not (shape & 8):  # one-shot then 0
            lv = np.where(ramp == 0, step if att else 15-step, 0)
        else:
            alt, hold = bool(shape & 2), bool(shape & 1)
            if hold:
                first = step if att else 15-step
                held = (15 if att else 0) ^ (15 if alt else 0)
                lv = np.where(ramp == 0, first, held)
            else:
                dirup = att ^ (alt & (ramp % 2 == 1))
                lv = np.where(dirup, step, 15-step)
        return lv
    
    phase = np.zeros(3)
    nphase, epos, eshape = 0.0, 1e9, 0
    outA, outB, outC = [], [], []
    idx = np.arange(1, N+1)
    for r, trig in regs_per_frame:
        if trig is not None:
            epos, eshape = 0.0, trig
        ep = max(1, r[11] | (r[12] << 8))
        estep = CLOCK/(16*ep)/SRO
        epos_arr = epos + estep*idx
        epos = epos_arr[-1]
        elev = VOL[env_levels(epos_arr, eshape)]
        npd = max(1, r[6] & 31)
        narr = nphase + CLOCK/(16*npd)/SRO*idx
        nphase = narr[-1] % 131071
        nb = bits[np.floor(narr).astype(np.int64) % 131071]
        chans = []
        for i in range(3):
            tp = max(1, r[i*2] | (r[i*2+1] << 8))
            f = CLOCK/(16*tp)
            if f > SRO/2:   # inaudible ultrasonic -> treat as constant high
                tbit = np.ones(N, dtype=bool)
            else:
                parr = phase[i] + f/SRO*idx
                phase[i] = parr[-1] % 1
                tbit = (parr % 1) < 0.5
            tdis = bool(r[7] & (1 << i))
            ndis = bool(r[7] & (1 << (i+3)))
            gate = (tbit | tdis) & (nb.astype(bool) | ndis)
            lvl = elev if r[8+i] & 0x10 else VOL[r[8+i] & 15]
            chans.append(gate*lvl)
        outA.append(chans[0]); outB.append(chans[1]); outC.append(chans[2])
    
    A, B, C = (np.concatenate(x) for x in (outA, outB, outC))
    L = A + 0.6*B + 0.2*C
    R = C + 0.6*B + 0.2*A
    st = np.stack([L, R], 1)
    st = resample_poly(st, 1, OS, axis=0)
    # DC removal
    from scipy.signal import butter, sosfilt
    st = sosfilt(butter(2, 20, 'hp', fs=SR, output='sos'), st, axis=0)
    st = st/np.max(np.abs(st))*0.89
    wavfile.write(path, SR, (st*32767).astype(np.int16))
    
