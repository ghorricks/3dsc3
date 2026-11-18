"""Original AY-3-8912 tune in the style of Tim Follin's 128K Spectrum music.
Generates a per-frame (50 Hz) register stream, writes a .psg file and renders audio."""
import math, struct, numpy as np
from scipy.signal import resample_poly
from scipy.io import wavfile

CLOCK = 1773400
FPS = 50
F16 = 4  # frames per 16th note

NOTE = {'C':0,'C#':1,'D':2,'D#':3,'E':4,'F':5,'F#':6,'G':7,'G#':8,'A':9,'A#':10,'B':11}
def midi(n):
    name, octv = n[:-1], int(n[-1])
    return 12*(octv+1) + NOTE[name]
def period(m):  # fractional midi allowed
    f = 440*2**((m-69)/12)
    return max(1, min(4095, round(CLOCK/(16*f))))

def parse(s):
    out = []
    for tok in s.split():
        n, l = tok.split(':')
        out.append((None if n == 'r' else midi(n), int(l)))
    return out

# ---------------------------------------------------------------- score
CH = {'Am':['A4','C5','E5'],'F':['F4','A4','C5'],'G':['G4','B4','D5'],'Em':['E4','G4','B4'],
      'E':['E4','G#4','B4'],'Dm':['D4','F4','A4'],'C':['C4','E4','G4'],'E7':['E4','G#4','D5']}
ROOT = {'Am':'A2','F':'F2','G':'G2','Em':'E2','E':'E2','Dm':'D2','C':'C2','E7':'E2'}

A_chords = ['Am','F','G','Em','Am','F','G','E']
A1 = ("E5:3 A5:3 E5:2 C5:2 D5:2 E5:4 F5:3 E5:3 C5:2 A4:4 C5:4 D5:3 B4:3 G4:2 B4:2 D5:2 G5:4 "
      "G5:3 E5:3 B4:2 E5:8 A5:2 G5:2 E5:2 A5:2 G5:2 E5:2 C5:2 E5:2 F5:2 E5:2 C5:2 F5:2 E5:2 C5:2 A4:2 C5:2 "
      "B4:3 C5:3 D5:2 G5:3 F5:3 D5:2 E5:10 G#5:2 B5:2 G#5:2")
A2 = ("E5:3 A5:3 E5:2 C5:2 D5:2 E5:4 F5:3 E5:3 C5:2 A4:4 C5:4 D5:3 B4:3 G4:2 B4:2 D5:2 G5:4 "
      "G5:3 E5:3 B4:2 E5:8 C6:4 B5:2 A5:2 E5:4 A5:4 C6:4 A5:2 F5:2 C5:4 F5:4 "
      "D6:3 B5:3 G5:2 D6:3 B5:3 G5:2 B5:4 G#5:4 E5:4 B4:4")
B_chords = ['Dm','G','C','Am','F','Dm','E','E']
B1 = "D5:6 F5:6 A5:4 B5:8 A5:4 G5:4 E5:6 G5:6 C6:4 A5:16 A5:6 C6:6 F5:4 F5:4 E5:4 D5:4 F5:4 E5:8 G#5:8 B5:16"
B2 = "D6:6 C6:6 A5:4 B5:6 G5:6 D5:4 E5:4 G5:4 C6:8 E6:8 C6:4 A5:4 F5:6 A5:6 C6:4 D6:8 F6:8 E6:8 B5:8 G#5:4 B5:4 E6:8"
K_chords = ['Am','Am','F','F','G','G','E','E']
K1 = "r:64 D6:16 B5:16 B5:16 G#5:16"
O_chords = ['Am','Am','Am','Am']
O1 = "A5:6 E6:6 A6:36 r:16"

# drum patterns (16 steps): K kick, S snare, h hat, . nothing
D_main = "K.h.S.hKK.h.S.h."
D_alt  = "K.h.S.hKK.hKS.hS"
D_fill = "K.S.S.SSK.SSSSSS"
D_brk  = "K.......K.K....."
D_hats = "h.h.h.h.h.h.h.hh"

# sections: (chords, lead, lead_mode, b_mode, bass_mode, drums list)
sections = []
def sec(chords, lead, bmode, bass, drums):
    sections.append((chords, lead, bmode, bass, drums))

sec(A_chords, "r:128", 'arp', 'bounce', ['']*4 + [D_hats]*3 + [D_fill])      # intro
sec(A_chords, A1, 'arp', 'bounce', [D_main, D_alt]*3 + [D_main, D_fill])
sec(A_chords, A2, 'arp', 'bounce', [D_main, D_alt]*3 + [D_main, D_fill])
sec(B_chords, B1, 'echo', 'bounce', [D_main, D_alt]*3 + [D_main, D_fill])
sec(B_chords, B2, 'echo', 'bounce', [D_main, D_alt]*3 + [D_main, D_fill])
sec(K_chords, K1, 'arp', 'buzz', [D_brk]*7 + [D_fill])
sec(A_chords, A1, 'echo', 'buzz', [D_main, D_alt]*3 + [D_main, D_fill])
sec(A_chords, A2, 'arp', 'bounce', [D_main, D_alt]*3 + [D_main, D_fill])
sec(O_chords, O1, 'arp', 'bounce', ["K.h.S.hKK.h.S.h.", "K.h.S.hKK.SSSSSS", "K...............", "................"])

# ---------------------------------------------------------------- render to frames
def expand_lead(seq):
    """-> per-frame list of (midi or None, frames_since_note_on, prev_midi)"""
    out, prev = [], None
    for m, l in seq:
        for t in range(l*F16):
            out.append((m, t, prev))
        if m is not None:
            prev = m
    return out

frames = []  # each: dict of channel states
for chords, lead, bmode, bass, drums in sections:
    nbars = len(chords)
    lf = expand_lead(parse(lead))
    assert len(lf) == nbars*16*F16, (lead, len(lf)/(16*F16), nbars)
    for bar in range(nbars):
        ch = chords[bar]
        root = midi(ROOT[ch])
        tones = [midi(n) for n in CH[ch]]
        for f in range(16*F16):
            gi = bar*16*F16 + f
            step, sub = divmod(f, F16)
            st = {}
            # --- channel A: lead
            m, t, prev = lf[gi]
            if m is None:
                st['A'] = (0, 0, False, False)
            else:
                pm = m
                if t < 3 and prev is not None and abs(prev-m) <= 7:   # portamento from previous
                    pm = prev + (m-prev)*(t+1)/3
                elif t < 2:
                    pm = m - 0.6 + 0.3*t                              # scoop
                if t > 10:
                    depth = min(0.35, 0.03*(t-10))
                    pm += depth*math.sin(2*math.pi*(t-10)/7)
                vol = 15 if t < 3 else max(11, 15-(t-3)//4)
                st['A'] = (period(pm), vol, True, False)
            # --- channel B: arp or echo
            if bmode == 'arp':
                am = tones[gi % 3] + (12 if (f//32) % 2 else 0)
                tt = f % 8
                vol = max(6, 12 - tt)
                st['B'] = (period(am), vol, True, False)
            else:
                d = 9  # echo delay in frames
                em, et, _ = lf[gi-d] if gi >= d else (None, 0, None)
                if em is None:
                    st['B'] = (period(tones[0]), 0, True, False)
                else:
                    em2 = em + (0.12*math.sin(2*math.pi*et/7) if et > 10 else 0) + 0.08  # slight detune
                    st['B'] = (period(em2), 9 if et < 4 else 8, True, False)
            # --- channel C: bass
            if bass == 'bounce':
                pat = [0, 12, 0, 12, 0, 12, 7, 12]
                eighth, et = divmod(f, 8)
                bm = root + pat[eighth]
                vol = 15 if et < 2 else (13 if et < 6 else 9)
                st['C'] = (period(bm), vol, True, False)
                st['env'] = None
            else:
                pat = [0, 0, 12, 0, 0, 12, 0, 10]
                eighth, et = divmod(f, 8)
                bm = root + pat[eighth] - 12 + 12  # A2 region
                tp = period(bm)
                st['C'] = (tp, 16, True, False)
                st['env'] = (max(1, round(tp/16)), 0x08 if eighth % 2 == 0 else 0x0C, et == 0)
            # --- drums
            dp = drums[bar] if drums[bar] else '.'*16
            # find most recent drum hit in this step or previous
            hit, age = None, None
            for back in range(0, 2):
                s2 = step - back
                if s2 >= 0 and dp[s2] != '.':
                    a = back*F16 + sub
                    if (dp[s2] == 'h' and a < 2) or (dp[s2] == 'S' and a < 5) or (dp[s2] == 'K' and a < 4):
                        hit, age = dp[s2], a
                    break
            st['noise'] = None
            if hit == 'K':
                kp = [0x180, 0x280, 0x3c0, 0x600][age]
                st['C'] = (kp, [15, 15, 13, 11][age], True, age == 0)
                st['noise'] = 2
                st['env_kill'] = True
            elif hit == 'S':
                st['C'] = (0x120 + age*40, [15, 14, 12, 10, 8][age], age < 2, True)
                st['noise'] = [6, 7, 8, 9, 10][age]
                st['env_kill'] = True
            elif hit == 'h':
                st['B'] = (st['B'][0], [10, 6][age], False, True)
                st['noise'] = 1
            frames.append(st)

# ---------------------------------------------------------------- registers
regs_per_frame = []
cur_env_period = 0
for st in frames:
    r = [0]*14
    trig = None
    mixer = 0x3F
    for i, c in enumerate('ABC'):
        tp, vol, tone, noise = st[c]
        r[i*2] = tp & 0xFF
        r[i*2+1] = (tp >> 8) & 0x0F
        if c == 'C' and vol == 16 and not st.get('env_kill'):
            r[10] = 0x10
        else:
            r[8+i] = min(15, vol)
        if tone: mixer &= ~(1 << i)
        if noise: mixer &= ~(1 << (i+3))
    r[7] = mixer
    r[6] = st['noise'] if st['noise'] else 1
    env = st.get('env')
    if env and not st.get('env_kill'):
        ep, shape, retrig = env
        r[11], r[12] = ep & 0xFF, ep >> 8
        if retrig:
            trig = shape
    elif env and st.get('env_kill'):
        r[11], r[12] = env[0] & 0xFF, env[0] >> 8
    regs_per_frame.append((r, trig))

# ensure envelope always triggered when entering env mode
prev_env = False
fixed = []
for r, trig in regs_per_frame:
    using = bool(r[10] & 0x10)
    if using and not prev_env and trig is None:
        trig = 0x08
    prev_env = using
    fixed.append((r, trig))
regs_per_frame = fixed

# ---------------------------------------------------------------- PSG file
with open('/home/claude/Storm_Runner.psg', 'wb') as fp:
    fp.write(b'PSG\x1a' + bytes([0x10, FPS]) + bytes(10))
    last = [None]*14
    for r, trig in regs_per_frame:
        fp.write(b'\xff')
        for i in range(13):
            if r[i] != last[i]:
                fp.write(bytes([i, r[i]]))
                last[i] = r[i]
        if trig is not None:
            fp.write(bytes([13, trig]))
    fp.write(b'\xfd')

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
wavfile.write('/home/claude/Storm_Runner.wav', SR, (st*32767).astype(np.int16))
print('frames', len(frames), 'seconds', len(frames)/FPS)
