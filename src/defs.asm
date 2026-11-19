; ---- Stock Car Next : shared definitions (sjasmplus) ----
PORT_NEXTREG_SEL    equ $243B
PORT_NEXTREG_DAT    equ $253B
PORT_KEMP1          equ $1F
PORT_KEMP2          equ $37
PORT_AY_REG         equ $FFFD
PORT_AY_DAT         equ $BFFD
PORT_L2             equ $123B
PORT_SPR_SEL        equ $303B
PORT_SPR_ATTR       equ $57
PORT_SPR_PAT        equ $5B

REG_TURBO           equ $07
REG_JOY_MODE        equ $05
REG_L2_ACTIVE       equ $12
REG_MMU0            equ $50
REG_MMU1            equ $51
REG_MMU2            equ $52
REG_MMU3            equ $53
REG_MMU6            equ $56
REG_MMU7            equ $57
REG_PAL_IDX         equ $40
REG_PAL_VAL8        equ $41
REG_PAL_CTRL        equ $43
REG_SPR_LAYERS      equ $15
REG_SPR_TRANS       equ $4B

TRACK_W             equ 256
TRACK_H             equ 192
TRACK_YOFF          equ 0
BANK_WALL           equ $C000          ; fence BASE plane (174 rows x 32 bytes)
BANK_GROUND         equ $D800          ; ground plane (inside the outer fence)
BANK_PROG           equ $F000          ; 64x48 progress cells (4px each)
BANK_PATHX          equ $FC00          ; lane centreline waypoints (<=250)
BANK_PATHY          equ $FD00
BANK_PATHH          equ $FE00          ; heading of the lane at each waypoint
CPU_N               equ 4
CPU_SZ              equ 34

; pad bits (MD mode, port $1F)
PAD_R   equ 0
PAD_L   equ 1
PAD_D   equ 2
PAD_U   equ 3
PAD_B   equ 4
PAD_C   equ 5
PAD_A   equ 6
PAD_ST  equ 7

CLEAN_PG            equ 100            ; 8K pages 100-105 = clean copy of the track image
FENCE_H             equ 5
REV_MAX             equ 100
NHEAD               equ 32

dist_arr            equ $2000          ; 256-byte scratch while the track is drawn: 8K page 106 mapped into MMU1 (the end of the track bank now holds the surface block)
BOOST_FRAMES      equ 100            ; 2 seconds at 50 Hz
