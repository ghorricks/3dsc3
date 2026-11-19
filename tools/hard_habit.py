"""'Hard Habit' - original AY tune in the style of 'Easy Lover'.
48 bars @ 128 bpm = exactly 90.00 s (4500 frames @ 50 Hz), loopable:
the opening build-up is mirrored at the end, finishing on the lone bass riff."""
import math, bisect
from ay_engine import midi, period, parse, states_to_regs, write_psg, render

BPM = 128
LEAD_SHIFT = -24          # lead two octaves down for the first half
LEAD_SHIFT_2 = -12        # ...then up an octave
LIFT_BAR = 24             # 0-based: bar 25, second hook (0:45, the halfway point)
F16 = 50*60/(BPM*4)            # 5.859375 frames per 16th
sf = lambda k: math.ceil(k*F16 - 1e-9)   # first frame of 16th-step k
NBARS = 48
TOTAL = sf(NBARS*16)           # 4500
SCALE = [2, 4, 5, 7, 9, 10, 0]   # D natural minor

def third_up(m):
    pc = m % 12
    if pc not in SCALE: return m + 4
    i = SCALE.index(pc); t = SCALE[(i+2) % 7]
    return m + ((t - pc) % 12)

CH = {'Dm': ['D4', 'F4', 'A4'], 'C': ['C4', 'E4', 'G4'], 'Bb': ['A#3', 'D4', 'F4']}
ROOT = {'Dm': 'D2', 'C': 'C2', 'Bb': 'A#1'}

# ---------------------------------------------------------------- material
HOOK = "A5:3 A5:3 G5:2 A5:4 D6:4 C6:3 A5:3 G5:2 E5:8 F5:3 G5:3 A5:2 D6:3 C6:3 A5:2 G5:12 r:4"
HOOK_CH = ['Dm', 'C', 'Bb', 'C']
VERSE_A = "r:2 D5:2 F5:2 D5:2 A5:4 G5:2 F5:2 E5:3 C5:3 E5:2 G5:6 r:2"
VERSE_B = "r:2 D5:2 F5:2 D5:2 A5:4 G5:2 F5:2 G5:3 A5:3 C6:2 A5:8"
BRIDGE = "D6:4b C6:2 A5:2 C6:4 D6:4 E6:4b D6:2 C6:2 G5:8 F5:2 G5:2 A5:2 C6:2 D6:4 F6:4b D6:16"
RIFF = "D2:2 D2:2 D3:2 D2:2 C3:2 D2:2 F2:2 G2:2"      # 1-bar build riff

# drum bars: K kick S gated snare h hat  H/M/L toms
NONE  = "................"
PULSE = "K.h.K.h.K.h.K.h."
BACK  = "K.h.S.h.K.h.S.h."
MAIN  = "K.h.S.h.K.hKS.h."
DRIVE = "K.hhS.hhK.hKS.hh"
TOMS  = "K.h.S.h.HHMMLLLL"
TFILL = "S.S.H.H.M.M.L.L."

bars = []   # per bar: chord, lead(seq str|None for that bar handled below), B, C, drums, swell
lead_parts = []  # (start_bar, seq string)
def add(chords, B, C, drums, lead=None, swell=None):
    if lead: lead_parts.append((len(bars), lead))
    for i, c in enumerate(chords):
        bars.append(dict(ch=c, B=B[i] if isinstance(B, list) else B,
                         C=C[i] if isinstance(C, list) else C, dr=drums[i],
                         sw=swell[i] if swell else 1.0))

# 1-8   build-up
add(['Dm']*8, ['off']*4 + ['stab']*4, 'riff',
    [NONE, NONE, PULSE, PULSE, BACK, BACK, MAIN, TOMS],
    swell=[1, 1, 1, 1, .35, .55, .8, 1])
# 9-16  hook x2
add(HOOK_CH*2, 'stab', 'pump', [DRIVE]*7 + [TFILL], lead=HOOK + " " + HOOK)
# 17-24 verse (2-bar phrase x4)
add(['Dm', 'C']*4, 'stab', 'pump', [MAIN]*7 + [TOMS],
    lead=" ".join([VERSE_A]*3 + [VERSE_B]))
# 25-32 hook x2 with harmony
add(HOOK_CH*2, 'harm', 'pump', [DRIVE]*7 + [TFILL], lead=HOOK + " " + HOOK)
# 33-36 bridge
add(['Bb', 'C', 'Dm', 'Dm'], 'stab', 'pump', [MAIN]*3 + [TOMS], lead=BRIDGE)
# 37-40 final hook with harmony
add(HOOK_CH, 'harm', 'pump', [DRIVE]*3 + [TFILL], lead=HOOK)
# 41-48 build-down: mirror of the opening
add(['Dm']*8, ['stab']*4 + ['off']*4, 'riff',
    [MAIN, TOMS, BACK, BACK, PULSE, PULSE, NONE, NONE],
    swell=[1, .8, .55, .35, 1, 1, 1, 1])
assert len(bars) == NBARS

# lead timeline (16th units)
lead_ev = []
for b0, s in lead_parts:
    pos = b0*16
    for m, l, fl in parse(s):
        if m is not None: lead_ev.append((pos, l, m + (LEAD_SHIFT if pos < LIFT_BAR*16 else LEAD_SHIFT_2), fl))
        pos += l
lead_starts = [e[0] for e in lead_ev]
riff_ev = []
pos = 0
for m, l, fl in parse(RIFF):
    riff_ev.append((pos, l, m)); pos += l
assert pos == 16

def active(evs, starts, k16):
    i = bisect.bisect_right(starts, k16) - 1
    if i >= 0 and evs[i][0] + evs[i][1] > k16: return i
    return None

STAB = "x..x..x...x.x..."
PUMP = [0, 0, 12, 0, 0, 12, 0, 7]

frames = []
for gi in range(TOTAL):
    k16f = gi/F16
    k16 = int(k16f + 1e-9)
    bar, step = divmod(k16, 16)
    B = bars[bar]
    tones = [midi(n) for n in CH[B['ch']]]
    root = midi(ROOT[B['ch']])
    st = {'env': None, 'noise': None}
    # ---------- A: lead
    li = active(lead_ev, lead_starts, k16)
    lm = None
    if li is not None:
        s0, l, m, fl = lead_ev[li]
        t = gi - sf(s0); ln = sf(s0+l) - sf(s0)
        prev = lead_ev[li-1][2] if li > 0 and lead_ev[li-1][0]+lead_ev[li-1][1] == s0 else None
        pm = m
        if 'b' in fl and t < 6: pm = m - 2 + 2*(t/6)**0.7
        elif prev is not None and t < 2 and abs(m-prev) <= 4: pm = prev + (m-prev)*(t+1)/2
        elif t < 2: pm = m - 0.4 + 0.2*t
        if t > 10: pm += min(0.3, 0.03*(t-10))*math.sin(2*math.pi*(t-10)/7)
        vol = 14 if t < 4 else max(11, 14 - (t-4)//8)
        if ln - t <= 1: vol -= 4
        st['A'] = (period(pm), vol, True, False)
        lm = (m, t, fl, vol)
    else:
        st['A'] = (1, 0, False, False)
    # ---------- B: stabs / harmony
    if B['B'] == 'stab':
        last = max([i for i in range(step+1) if STAB[i] == 'x'], default=None)
        if last is None:
            st['B'] = (1, 0, False, False)
        else:
            age = gi - sf(bar*16 + last)
            am = tones[gi % 3] + 12
            v = max(0, 13 - 2*age) if age < 9 else 0
            st['B'] = (period(am), round(v*B['sw']), True, False)
    elif B['B'] == 'harm' and lm:
        m, t, fl, vol = lm
        ph = third_up(m) + 0.07
        if 'b' in fl and t < 6: ph -= 2*(1-(t/6)**0.7)
        if t > 10: ph += 0.2*math.sin(2*math.pi*(t-10)/7 + 1.2)
        st['B'] = (period(ph), max(0, vol-3), True, False)
    else:
        st['B'] = (1, 0, False, False)
    # ---------- C: bass
    if B['C'] == 'riff':
        r = [e for e in riff_ev if e[0] <= step < e[0]+e[1]][0]
        t = gi - sf(bar*16 + r[0]); ln = sf(bar*16 + r[0] + r[1]) - sf(bar*16 + r[0])
        vol = 15 if t < 3 else 12
        if ln - t <= 1: vol = 5
        st['C'] = (period(r[2]), vol, True, False)
    else:
        e8 = step // 2
        t = gi - sf(bar*16 + e8*2); ln = sf(bar*16 + e8*2 + 2) - sf(bar*16 + e8*2)
        vol = 15 if t < 3 else 12
        if ln - t <= 1: vol = 5
        st['C'] = (period(root + PUMP[e8]), vol, True, False)
    # ---------- drums
    dp = B['dr']
    hit = age = None
    for back in (0, 1):
        s2 = step - back
        if s2 >= 0 and dp[s2] != '.':
            a = gi - sf(bar*16 + s2)
            if a < {'h': 2, 'S': 8, 'K': 5, 'H': 7, 'M': 7, 'L': 7}[dp[s2]]: hit, age = dp[s2], a
            break
    if hit == 'K':
        st['C'] = ([0x1c0, 0x300, 0x480, 0x700, 0x900][age], [15, 15, 14, 12, 9][age], True, age == 0)
        st['noise'] = 3
    elif hit == 'S':     # big gated snare: loud plateau then hard cut
        st['C'] = (0x130 + age*30, [15, 15, 15, 14, 14, 13, 13, 0][age], age < 2, True)
        st['noise'] = [4, 5, 6, 6, 7, 7, 8, 8][age]
    elif hit and hit in 'HML':   # Collins-style toms
        p0 = {'H': 0x0d0, 'M': 0x130, 'L': 0x1b0}[hit]
        st['C'] = (int(p0*1.13**age), [15, 15, 14, 13, 11, 9, 7][age], True, age == 0)
        st['noise'] = 6
    elif hit == 'h':
        st['B'] = (st['B'][0], [9, 5][age], False, True)
        st['noise'] = 1
    frames.append(st)

# fade out over the last 4 seconds (200 frames); the tune then loops with no fade in
FADE = 200
for i in range(TOTAL-FADE, TOTAL):
    g = (TOTAL-1-i)/FADE
    for c in 'ABC':
        tp, v, tn, ns = frames[i][c]
        frames[i][c] = (tp, int(round(v*g)), tn, ns)
regs = states_to_regs(frames)
write_psg(regs, '/home/claude/stockcar/tools/Hard_Habit.psg')
render(regs, '/tmp/cap/Hard_Habit.wav')
print('frames', len(frames), 'seconds', len(frames)/50)
