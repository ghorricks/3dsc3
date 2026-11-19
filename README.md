# 3D Stock Car Championship - ZX Spectrum Next remake (milestone 5)
Run `stockcar.nex` on a ZX Spectrum Next (or CSpect/emulator with Next support).
Controls: pad (M30) A/B accelerate, C brake, Down reverse, L/R steer, Start to skip/start.
Keyboard: Q accel, A reverse, Z brake, O/P steer, Enter start.
Build: `python3 -I tools/build_data.py` then `sjasmplus --sym=build/main.sym main.asm`.
Status: 24 traced tracks, clean 3D fences (base = barrier), 3D car, 32 headings, CCW start, track board, HUD.
Not yet: AI cars, 4-player setup/laps, qualifying flow, intro, hi-score table, sound per car.

## Boost
Each time you cross the start/finish line and complete a lap (practice included) one boost is banked, up to 3
(shown as `B3` at the top right of the HUD; `+` appears while a boost is running). Press **D-pad Up** on the pad
(keyboard: **W**) to spend one: top speed is 1.5x for 2 seconds.

## Versioning
Builds are named `3DSC3_YYMMDDxx.nex` (xx = 01..99, restarting each day). The same number is shown at the bottom right of the
menu and track screens (`s_ver` in main.asm - update it with every delivered build).

## Menu, cars and grid (build 26111707)
- Main menu: CAR 1-4 each get a controller (KEMPSTON 1, KEMPSTON 2, INT2 L, INT2 R, CURSOR, KEYS QAOPSP, COMPUTER, UNWANTED), then DIFFICULTY (EASY/MEDIUM/EXPERT), TRACK, LAPS (PRACTICE/3/5/10), START, INSTRUCTIONS. Q/A or joystick up/down move, O/P or left/right change, fire (Space/Enter/pad button) selects.
- Computer cars race on all 24 tracks (a baked lane path per track, built by tools/build_data.py; hand way-points for the figure-8 / serpentine tracks). They are stopped by fences (they slide along them), reverse out when wedged, swing out to overtake and each has a slightly different pace.
- Starting grid: staggered two-by-two behind the line (3 directly behind 1, 4 directly behind 2), centred on the road, each slot marked with a white "[" with its closed line at the front and the sides running back.
- Race ends when a car completes the chosen laps (winner shown); practice ends when the 3:00 countdown reaches zero.

## Session flow (build 26111709)
Practice (3:00 countdown, lap times in the top row) -> results screen (#1..#4 by best lap) -> SPACE -> race: grid, traffic light (red, yellow, green, cars held until green), top row shows each car's position and laps remaining ("1  3L") with 1234 in the middle in the colours of the cars in those places -> race results -> menu. LAPS = PRACTICE ONLY skips the race. Enter, pad START or BREAK opens the CONTINUE / END RACE / QUIT menu.
Car graphics are stored as nibbles (80 bytes per heading) and unpacked per car per frame.

## Best laps (build 26111714)
Top 10 lap times per track (24 x 10, name + tenths) live in RAM page 110, mapped at $E000 only while used. All start as 3DSC3 99.9S. After a race each human car whose best lap makes the table enters a 5-character name (up/down cycle A-Z 0-9 space, fire = confirm and move on, left = back; the next character starts at A). BEST LAPS on the main menu shows the table, left/right changes track. The table is not saved to disk: it is cleared at power-off / reset.
Defaults: difficulty MEDIUM, 6 laps. All screens are centred. Free code space below $C000 is only ~10 bytes.

## Saved best laps / lap flash
Best laps are written to `3DSC3.SAV` (1920 bytes, raw table) through esxDOS (`rst $08`) after new records are entered, and read back at start-up. The file code lives in the hi-score page (page 80, `$E800`). After a timed lap the car's `LAPS n` shows the lap time for 3 s.

## Online best laps
`src/hiscore.asm` now lives in RAM page 80 (mapped at `$E000`; stubs in main.asm). Entries carry a synced flag (byte 7). After names are entered the table is saved to `3DSC3.SAV`, then every unsynced record is sent with
`.http get -h <host> -u /?track=N&name=XXXXX&time=SS.T` (via esxDOS M_EXECCMD, run from main memory). At start-up any unsynced records are sent the same way (stops at the first failure).
The Best Laps screen has LOCAL / ONLINE views (up/down); ONLINE does a single `.http ... -u /?track=all` into bank 41 (page 82) and parses the `T,NAME,SS.T` lines into a cache (counts at `$D000`, 10 x 8 bytes per track at `$D100`); switching track or LOCAL/ONLINE afterwards uses the cache, and it is refetched after new records are sent. `.http` has no HTTPS: `net_host` must be reachable over plain HTTP.


## Music
The menu tune is 'Hard Habit' (tools/hard_habit.py, AY engine in tools/ay_engine.py): 90 s, the last 4 s fade out, then it loops with no fade-in. tools/mkmusic.py packs tools/Hard_Habit.psg into the music pages.

## Fence geometry rules (all tracks, 12 onwards use them in tools/vecfence.py with CLEAN=True)
The playfield is an isometric view, so a fence only ever runs in one of four directions: **level** (same Y along its whole length),
**2:1 diagonal** either way, or the 3D "vertical" direction, which is a **shear**: 1 pixel across for every 4 down (leaning left going down),
exactly like the far-right fence of the originals. Never plumb vertical. Free wall ends keep the wall's own direction (no hooks); two level
pieces that meet end to end share one Y. When designing a new track, draw only these directions.
