; =====================================================================
PROMPT_C    equ 41
;  STOCK CAR NEXT  -  milestone 3
;  clean 3D fences (collision on the fence BASE), cars drawn behind/in front of
;  fences, 3D car model, 32 headings, counter-clockwise starts, reverse, number board.
;  Assemble:  sjasmplus --nologo main.asm        -> stockcar.nex
; =====================================================================
        DEVICE ZXSPECTRUMNEXT
        INCLUDE "src/defs.asm"

GRASS       equ 32
SURF_BLK    equ $FF00                           ; per-track surface block at the end of the track bank (tools/surfaces.py)
SURF_TYRE   equ $FF44
SURF_INF    equ $FF28                           ; 220 bits, one per tree try: 1 = infield
SURF_OUT    equ $FF84
        ORG $8000
start:
        di
        ld sp,dc_lut
        nextreg REG_TURBO,3             ; 28 MHz
        call init_hw
        call input_init
        ld bc,PORT_NEXTREG_SEL : ld a,8 : out (c),a : inc b : in a,(c) : or 2 : out (c),a   ; TurboSound on (three AY chips)
        call ay_init
        im 2 : ld a,high mus_vec : ld i,a                 ; the tune runs from the frame interrupt (only enabled outside the race)
        xor a : call title_show                         ; the title picture stays up while the saved records load and the server is asked about a newer build
        call hs_init
        xor a
        ld (track_idx),a

; ------------------------------------------------------------------ menu
menu:
        ld a,(trk_max) : ld b,a : ld a,(track_idx) : cp b : jr c,.tk : xor a : ld (track_idx),a      ; only the finished tracks are on offer (unless DEBUG)
.tk:    call mus_resume                 ; music plays on every screen but the race
        call menu_run                   ; returns when START is chosen
        xor a : ld (phase),a            ; every visit starts with practice
; ------------------------------------------------------------------ practice / race session
session:
        call hs_pre                     ; online best laps, fetched once per round before the track is drawn
        call mus_off                    ; the race screen has the engines, not the tune
        xor a : out ($FE),a                         ; border: set from the surface once the palette is loaded
        call get_meta
        call map_track
        call load_palette
        call render_track               ; clean image -> clean copy pages
        call copy_clean_to_l2
        call draw_board
        call draw_startline
        call draw_grid                  ; "[" slot markings behind each starting position
        call draw_best                  ; bottom right: the track's best lap
        call map_track                  ; draw_best may have left a score page in the window: the surface scenery tables live in the track bank
        call draw_trees
        call hud_clear_old              ; nothing of the last race (places, flags, boosts, best laps) goes into the new top bar
        call hud_static
        call copy_l2_to_clean           ; board + grid + HUD labels become part of the clean copy
        call init_race
        call init_cpu
        ld a,(phase) : or a : call nz,init_rank
        ld a,1 : ld (hud_dirty),a
        call hs_ready                   ; black panel: PRESS FIRE TO START ..., time to get ready
.frame: call wait_frame
        call restore_all                            ; cars and HUD are redrawn first, while the beam is still in the border / top: the game logic runs while the picture is drawn
        call draw_all
        call hud_update
        call start_in
        bit STA,a : jr z,.nq
        call hs_quitq                               ; ENTER / pad START: CONTINUE, END RACE (PRACTICE) or QUIT TO MENU
        ld a,(qt_res) : or a : jr z,.nq
        cp 1 : jp nz,.quit
        jp .over
.nq:
        ld bc,$FEFE : in a,(c) : bit 0,a : jr nz,.np  ; BREAK (Caps Shift + Space): the same menu as ENTER / START
        ld b,$7F : in a,(c) : bit 0,a : jr nz,.np
        call game_keys : jr nz,.np                  ; (ghost key presses while driving are not BREAK)
.bw:    call wait_frame                             ; BREAK does what ENTER / START does (the menu pauses the race): let go of it first
        ld bc,$FEFE : in a,(c) : bit 0,a : jr nz,.bu
        ld b,$7F : in a,(c) : bit 0,a : jr z,.bw
.bu:    call hs_quitq
        ld a,(qt_res) : or a : jr z,.np
        cp 1 : jp nz,.quit
        jp .over
.np:
        ld a,(lt_s) : or a : jr z,.go
        call light_step                             ; traffic light: cars held on the grid until green
        or a : jr nz,.held
.go:    call update_cars
        call cars_collide
        call tick_time
        call lap_tick
        call best_tick
        call rank_update
        call sound_update
        call cpu_sound
.held:  call check_end
        ld a,(race_over) : or a : jp z,.frame
.over:  xor a : ld (vj_on),a : call mus_resume
        call show_results
        ld a,(phase) : or a : jr z,.pr
        ld a,(nxt_flag) : or a : jp z,menu          ; race over: MAIN MENU ...
        ld a,(trk_max) : ld b,a : ld a,(track_idx) : inc a : cp b : jr c,.nt  ; ... or the NEXT TRACK, starting with its practice
        xor a
.nt:    ld (track_idx),a : xor a : ld (phase),a : jp session
.pr:
        ld a,(laps_total) : or a : jp z,menu        ; practice only
        ld a,1 : ld (phase),a : jp session          ; on to the race
.quit:  call silence_all
        jp menu

silence_all:
        call ay_silence
        ld e,0 : ld a,10 : jp ay_write

end_in:                                             ; NZ when Symbol Shift and Space are both down
        ld bc,$7FFE : in a,(c) : and 3 : jr z,.y
        xor a : ret
.y:     call game_keys                              ; a membrane keyboard fakes Symbol Shift when Space, O and P are held: with a driving key down it is not an abort
        jr nz,.n
        ld a,1 : or a : ret
.n:     xor a : ret

game_keys:                                          ; NZ when any of Q A O P is down
        ld bc,$FBFE : in a,(c) : bit 0,a : jr z,.d
        ld b,$FD : in a,(c) : bit 0,a : jr z,.d
        ld b,$DF : in a,(c) : and 3 : cp 3 : jr nz,.d
        xor a : ret
.d:     or 1 : ret

check_end:                                          ; race: a car that has run all its laps takes its place and leaves the track; over when all have
        ld a,(race_over) : or a : ret nz
        ld a,(phase) : or a : ret z
        ld ix,cpu_t : ld b,CPU_N
.l:     push bc
        ld a,(ix+23) : or a : jr z,.n
        ld a,(laps_total) : cp (ix+24) : jr z,.fin
        jr nc,.n
.fin:   ld a,(fin_n) : inc a : ld (fin_n),a : ld (ix+29),a
        cp 1 : jr nz,.nj : ld a,(ix+23) : cp 1 : jr nz,.nj           ; a human takes first place as they cross the line: victory jingle on AY 2
        ld a,JING_PG : ld (mus_pg),a : ld hl,MUS_WIN : ld (mus_ptr),hl : ld a,1 : ld (mus_on),a : ld (vj_on),a
.nj:
        call cpu_swap : call restore_car : call cpu_swap
        ld (ix+23),0
        ld a,1 : ld (hud_dirty),a
.n:     ld de,CPU_SZ : add ix,de
        pop bc : djnz .l
        ld ix,cpu_t : ld b,CPU_N
.a:     ld a,(ix+23) : or a : ret nz                ; somebody is still racing
        ld de,CPU_SZ : add ix,de : djnz .a
        ld a,1 : ld (race_over),a
        ret
fin_n:  db 0

init_race:
        xor a : ld (race_over),a : ld (cd_f),a : ld (gf),a : ld (snd_skid),a : ld (snd_hit),a : ld (snd_cn),a : ld (bl_done),a : ld (bl_t),a : ld (cs_k),a : ld (lt_s),a : ld (fr_cnt),a : ld (fin_n),a
        call silence_all
        ld hl,180 : ld (cd_s),hl
        ld hl,0 : ld (lap_show),hl : ld (lap_show+2),hl
        ld a,1 : ld (hud_dirty),a
        ld a,(phase) : or a : ret z
        call light_pos                              ; race: red, yellow, green in front of the line
        ld a,1 : ld (lt_s),a : ld a,100 : ld (lt_t),a
        jp draw_light

; ---- traffic light: a post and a box with three lamps, ahead of the line in the middle of the road
light_pos:
        call grid_centre
        ld hl,(sl_x0) : ld (sl_x),hl : ld hl,(sl_y0) : ld (sl_y),hl
        ld a,(sl_h) : call sl_vec : ld b,10
.f:     call sl_adv : djnz .f
        ld a,(gc_off) : or a : jr z,.nsh
        ld b,a : ld a,(sl_h) : bit 7,b : jr nz,.sn
        add a,8 : jr .sv
.sn:    sub 8 : ld d,a : ld a,b : neg : ld b,a : ld a,d
.sv:    and 31 : call sl_vec
.sh:    call sl_adv : djnz .sh
.nsh:   ld a,(sl_x+1) : cp 8 : jr nc,.x1
        ld a,8
.x1:    cp 240 : jr c,.x2
        ld a,239
.x2:    ld (lt_x),a
        ld a,(sl_y+1) : cp 40 : jr nc,.ok
        ld a,40
.ok:    cp 190 : jr c,.ok2
        ld a,189
.ok2:   ld (lt_y),a
        ret

draw_light:
        ld a,(lt_x) : dec a : ld (fr_x),a : ld a,(lt_y) : sub 8 : ld (fr_y),a
        ld a,2 : ld (fr_w),a : ld a,9 : ld (fr_h),a : ld a,3 : ld (fr_c),a : call fill_rect      ; post
        ld a,(lt_x) : sub 4 : ld (fr_x),a : ld a,(lt_y) : sub 32 : ld (fr_y),a
        ld a,9 : ld (fr_w),a : ld a,24 : ld (fr_h),a : ld a,3 : ld (fr_c),a : call fill_rect     ; frame
        ld a,(lt_x) : sub 3 : ld (fr_x),a : ld a,(lt_y) : sub 31 : ld (fr_y),a
        ld a,7 : ld (fr_w),a : ld a,22 : ld (fr_h),a : xor a : ld (fr_c),a : call fill_rect       ; black face
        ld c,0
.l:     push bc
        ld a,(lt_x) : sub 2 : ld (fr_x),a
        ld a,c : ld e,a : add a,a : add a,a : add a,a : sub e : ld e,a            ; 7 * lamp
        ld a,(lt_y) : sub 30 : add a,e : ld (fr_y),a
        ld a,5 : ld (fr_w),a : ld (fr_h),a
        ld a,(lt_s) : dec a : cp c : ld hl,lamp_lit : jr z,.c                      ; the current colour is bright, the others dim
        ld hl,lamp_dim
.c:     ld b,0 : add hl,bc : ld a,(hl) : ld (fr_c),a : call fill_rect
        pop bc : inc c : ld a,c : cp 3 : jr c,.l
        ret
lamp_lit: db 24,28,20
lamp_dim: db 26,30,22

clear_light:                                        ; put the clean track back where the light stood
        ld a,(lt_x) : sub 4 : ld (rr_x),a
        ld a,(lt_y) : sub 32 : ld (rr_y),a
        ld b,34
.r:     push bc
        ld a,(rr_y) : ld b,a : rlca : rlca : and 3 : add a,a : ld e,a
        add a,18 : nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld a,e : add a,CLEAN_PG : nextreg REG_MMU2,a : inc a : nextreg REG_MMU3,a
        ld a,b : and 63 : ld d,a : ld a,(rr_x) : ld e,a : ld l,a : ld a,d : add a,$40 : ld h,a
        ld bc,9 : ldir
        ld hl,rr_y : inc (hl)
        pop bc : djnz .r
        ret

light_step:                                         ; one frame of the start sequence -> A = 1 while the cars are held
        ld hl,lt_t : dec (hl) : jr nz,.r
        ld a,(lt_s) : inc a : ld (lt_s),a
        cp 2 : jr nz,.g
        ld a,50 : ld (lt_t),a : call draw_light : jr .r
.g:     cp 3 : jr nz,.off
        ld a,70 : ld (lt_t),a : call draw_light : jr .r
.off:   call clear_light : xor a : ld (lt_s),a : ret
.r:     ld a,(lt_s) : cp 3 : ld a,1 : ret c
        xor a : ret

; ---- race order: crossings of the line, then how far round the lane
init_rank:
        call race_keys
        call rank_all
        ld hl,pos_ord : ld de,pos_old : ld bc,4 : ldir
        ret

rank_update:
        ld a,(phase) : or a : ret z
        ld a,(fr_cnt) : inc a : ld (fr_cnt),a : and 7 : ret nz
        call race_keys
        call rank_all
        call merge_finished                                ; cars past the flag keep the place they finished in
        ld hl,pos_ord : ld de,pos_old : ld b,4 : ld c,0
.c:     ld a,(de) : cp (hl) : jr z,.s
        inc c : ld a,(hl) : ld (de),a
.s:     inc hl : inc de : djnz .c
        ld a,c : or a : ret z
        ld a,1 : ld (hud_dirty),a
        ret

race_keys:                                          ; ro_key[slot] = 65535 - (crossings*256 + progress): smaller = further ahead
        ld ix,cpu_t : ld iy,ro_key : ld b,CPU_N
.l:     push bc
        ld a,(ix+23) : or a : jr z,.n
        cp 1 : jr nz,.cpu
        ld a,(npts) : or a : jr z,.hp
        call nearest_wp : ld c,a : jr .k             ; human on a track with a lane path
.hp:    ld l,(ix+26) : ld h,(ix+27) : ld de,lastp-pc_block : add hl,de : ld c,(hl) : jr .k
.cpu:   ld c,(ix+6)
.k:     ld a,(lt_s) : or a : jr z,.nl
        cp 3 : jr nc,.nl                                    ; lights not yet green: the order is the grid order
        push iy : pop hl : ld de,-ro_key : add hl,de : ld a,l : srl a : ld (iy+0),a : ld (iy+1),0 : jr .n
.nl:    ld a,(ix+28) : inc a : ld d,a : ld e,c                ; DE = 256 + crossings*256 + progress
        ld a,(ix+28) : or a : jr nz,.nb
        ld a,(npts) : or a : jr z,.nb
        srl a : cp c : jr nc,.nb                           ; still on the grid behind the line: progress counts as negative
        ld a,(npts) : ld l,a : ld h,0 : ex de,hl : or a : sbc hl,de : ex de,hl     ; DE = DE - npts
.nb:    ld a,e : cpl : ld (iy+0),a : ld a,d : cpl : ld (iy+1),a
.n:     ld de,CPU_SZ : add ix,de : inc iy : inc iy
        pop bc : djnz .l
        ret

rank_all:                                           ; active cars in order of ro_key (smaller first) -> pos_ord, ro_n
        xor a : ld (ro_n),a
        ld hl,ro_u : ld de,ro_u+1 : ld (hl),a : ld bc,3 : ldir
.r:     call rank_best : cp 255 : ret z
        ld e,a : ld d,0 : ld hl,ro_u : add hl,de : ld (hl),1
        ld hl,pos_ord : ld a,(ro_n) : ld c,a : ld b,0 : add hl,bc : ld (hl),e : inc a : ld (ro_n),a
        jr .r

rank_best:                                          ; best unranked active car -> A (255 = none)
        ld hl,$FFFF : ld (rb_key),hl : ld a,255 : ld (rb_slot),a
        ld ix,cpu_t : ld c,0 : ld b,CPU_N
.l:     ld a,(ix+23) : or a : jr z,.n
        ld hl,ro_u : ld e,c : ld d,0 : add hl,de : ld a,(hl) : or a : jr nz,.n
        ld hl,ro_key : add hl,de : add hl,de : ld e,(hl) : inc hl : ld d,(hl)
        ld a,(rb_slot) : inc a : jr z,.tk                                 ; first candidate is always taken
        ld hl,(rb_key) : or a : sbc hl,de : jr c,.n : jr z,.n
.tk:        ld (rb_key),de : ld a,c : ld (rb_slot),a
.n:     push de : ld de,CPU_SZ : add ix,de : pop de : inc c : djnz .l
        ld a,(rb_slot)
        ret

nxt_flag:   db 0
phase:      db 0                                    ; 0 practice, 1 race
lt_s:       db 0                                    ; traffic light: 0 off, 1 red, 2 yellow, 3 green
lt_t:       db 0
lt_x:       db 0
lt_y:       db 0
rr_x:       db 0
rr_y:       db 0
lc_hit:     db 0
rb_key:     dw 0
rb_slot:    db 0
ro_n:       db 0
ro_u:       ds 4
ro_key:     ds 8
pos_ord:    ds 4
pos_old:    ds 4

; ------------------------------------------------------------- hardware
init_hw:
        nextreg REG_L2_ACTIVE,9
        ld bc,PORT_L2 : ld a,2 : out (c),a          ; layer 2 visible
        nextreg REG_SPR_LAYERS,0                    ; sprites off (cars are drawn into Layer 2)
        xor a : out ($FE),a
        nextreg REG_PAL_CTRL,$10                    ; L2 first palette
        nextreg REG_PAL_IDX,0
        ld hl,pal_l2 : ld b,36
.pl:    ld a,(hl) : nextreg REG_PAL_VAL8,a : inc hl : djnz .pl
        nextreg REG_PAL_IDX,40 : nextreg REG_PAL_VAL8,$B6      ; fixed light grey for the grid markings (5-7 change with each track)
        nextreg REG_PAL_IDX,42 : nextreg REG_PAL_VAL8,$FC      ; 42 = pulsing colour of the records just set
        nextreg REG_PAL_IDX,41 : nextreg REG_PAL_VAL8,$1F      ; 41 = cyan: colour of every 'what to do next' prompt
        ret

wait_frame:                                         ; wait for raster line 192
        ld bc,PORT_NEXTREG_SEL
.w1:    ld a,$1F : out (c),a : inc b : in a,(c) : dec b
        cp 192 : jr nz,.w1
.w2:    ld a,$1F : out (c),a : inc b : in a,(c) : dec b
        cp 192 : jr z,.w2
        ld a,(mus_on) : or a : ret z
        ld bc,PORT_NEXTREG_SEL : ld a,REG_MMU6 : out (c),a : inc b : in a,(c) : push af      ; the channel bars and the menu car live in page 81
        nextreg REG_MMU6,LOGO_PG : call mus_viz
        pop af : nextreg REG_MMU6,a
        ret

border_black:                                       ; every screen that is not the track has the black border
        xor a : out ($FE),a : nextreg $4A,a
        nextreg REG_PAL_CTRL,0 : nextreg REG_PAL_IDX,16 : nextreg REG_PAL_VAL8,a : nextreg REG_PAL_CTRL,$10
        ret
clear_screen:
        call border_black
        ld hl,vz_car : inc (hl)                          ; a new screen: the menu car changes colour
        ld a,18
.w:     push af
        nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld hl,0 : ld de,1 : ld bc,$3FFF : ld (hl),0 : ldir
        pop af : add a,2 : cp 24 : jr c,.w
        ret

copy_clean_to_l2:
        xor a : ld (win_pg),a
.w:     call map_windows
        ld hl,$4000 : ld de,0 : ld bc,$4000 : ldir
        ld a,(win_pg) : inc a : ld (win_pg),a : cp 3 : jr c,.w
        ret

copy_l2_to_clean:
        xor a : ld (win_pg),a
.w:     call map_windows
        ld hl,0 : ld de,$4000 : ld bc,$4000 : ldir
        ld a,(win_pg) : inc a : ld (win_pg),a : cp 3 : jr c,.w
        ret

map_windows:                                        ; window (win_pg) -> L2 in slots 0/1, clean copy in slots 2/3
        ld a,(win_pg) : add a,a : ld b,a
        add a,18 : nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld a,b : add a,CLEAN_PG : nextreg REG_MMU2,a : inc a : nextreg REG_MMU3,a
        ret

l2_row_addr:                                        ; A = y, E = x -> DE = L2 address (window mapped)
        ld d,a : rlca : rlca : and 3 : add a,a : add a,18
        nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld a,d : and 63 : ld d,a
        ret

; ----------------------------------------------------------------- track
get_meta:                                           ; HL = meta entry (12 bytes)
        ld a,(track_idx) : ld l,a : ld h,0
        add hl,hl : add hl,hl : ld d,h : ld e,l
        add hl,hl : add hl,de
        ld de,track_meta : add hl,de
        ld (meta_ptr),hl
        ret

load_palette:                                       ; meta: +3 lo +4 mid +5 hi +6 post +7 road
        ld hl,(meta_ptr) : ld de,3 : add hl,de
        nextreg REG_PAL_CTRL,$10
        nextreg REG_PAL_IDX,1
        ld a,(hl) : nextreg REG_PAL_VAL8,a : inc hl
        ld b,(hl) : inc hl
        ld c,(hl) : inc hl
        ld d,(hl) : inc hl
        ld e,(hl)
        nextreg REG_PAL_IDX,2                       ; 9-bit colours: road and its darker twin differ only by the blue LSB
        ld a,e : nextreg $44,a : nextreg $44,1
        nextreg REG_PAL_IDX,12
        ld a,e : nextreg $44,a : nextreg $44,0
        nextreg REG_PAL_IDX,44                      ; dirt speckle shades: dark, light, mid-dark
        nextreg REG_PAL_VAL8,$68 : nextreg REG_PAL_VAL8,$AD : nextreg REG_PAL_VAL8,$68
        nextreg REG_PAL_IDX,5
        ld a,b : nextreg REG_PAL_VAL8,a
        ld a,c : nextreg REG_PAL_VAL8,a
        ld a,d : nextreg REG_PAL_VAL8,a
        ld a,e : cp $92 : ld a,$B6 : jr c,.mk       ; grid markings: light grey, but darker on a light road (track 3)
        ld a,$6D
.mk:    nextreg REG_PAL_IDX,40 : nextreg REG_PAL_VAL8,a
        ld hl,SURF_BLK+1 : ld b,(hl) : inc hl           ; this track's surface palette (road, ground, scenery, tyres, specks): n x (index, 9-bit colour)
.sp:    ld a,(hl) : inc hl : nextreg REG_PAL_IDX,a
        ld a,(hl) : inc hl : nextreg $44,a
        ld a,(hl) : inc hl : nextreg $44,a
        djnz .sp
        nextreg REG_PAL_CTRL,0 : nextreg REG_PAL_IDX,16                 ; the border (ULA paper 0) gets exactly the 9-bit colour of the surround (palette entry 32 of the surface block)
        ld a,(SURF_BLK+9) : nextreg $44,a : ld a,(SURF_BLK+10) : nextreg $44,a
        nextreg REG_PAL_CTRL,$10
        ld a,(SURF_BLK+9) : nextreg $4A,a                               ; the fallback colour (8-bit only) is the nearest
        xor a : out ($FE),a
        ret

map_track:                                          ; 16K bank 16+idx -> $C000-$FFFF
        ld a,(track_idx) : add a,a : add a,32
        cp 80 : jr nz,.mp : ld a,90                    ; track 25 lives past the music pages
.mp:    nextreg REG_MMU6,a : inc a : nextreg REG_MMU7,a
        ret

; Render the clean track image into the clean-copy pages, bottom row first so every
; fence pixel knows its distance above its base line (3D fence: base, panel, top rail, posts).
render_track:
        nextreg REG_MMU1,106
        ld hl,dist_arr : ld de,dist_arr+1 : ld bc,255 : ld (hl),255 : ldir
        ld a,191 : ld (cur_y),a
.row:   ld a,(cur_y) : ld b,a
        rlca : rlca : and 3 : add a,a : add a,CLEAN_PG
        nextreg REG_MMU2,a : inc a : nextreg REG_MMU3,a
        ld a,b : and 63 : add a,$40 : ld d,a : ld e,0
        ld a,b : sub TRACK_YOFF : jp c,.blank
        cp TRACK_H : jp nc,.blank
        ld l,a : ld h,0
        add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl
        push hl
        ld bc,BANK_WALL : add hl,bc : ld (wptr),hl
        pop hl
        ld bc,BANK_GROUND : add hl,bc : ld (gptr),hl
        ld a,32 : ld (bcnt),a
        ld hl,dist_arr
.byte:  push hl
        ld hl,(wptr) : ld c,(hl) : inc hl : ld (wptr),hl
        ld hl,(gptr) : ld b,(hl) : inc hl : ld (gptr),hl
        pop hl
        ld ixl,8
.bit:   rl b : sbc a,a : ld ixh,a                   ; ixh = FF if inside the outer fence
        rl c : jr nc,.nob
        ld a,(hl) : or a : ld a,1 : jr nz,.bset     ; fence base line (dark)
        ld a,5                                      ; base pixel directly below was also base: vertical run -> panel colour
.bset:  ld (hl),0 : jr .put
.nob:   ld a,(hl) : cp 200 : jr nc,.k
        inc a : ld (hl),a
.k:     cp FENCE_H+1 : jr nc,.nofence
        cp FENCE_H : jr nz,.mid
        ld a,6 : jr .put                            ; top rail
.mid:   ld a,l : and 7 : jr z,.post              ; post every 8 px
        ld a,(cur_y) : xor l : and 1 : jr z,.nofence ; chain-link: checkerboard holes show what is behind
        ld a,5 : jr .put
.post:  ld a,7 : jr .put
.nofence:
        ld a,ixh : and 2 : jr nz,.road
        ld a,(cur_y) : cp 12 : ld a,0 : jr c,.put   ; HUD strip (12 rows) stays black, including the far right column
        ld a,GRASS : jr .put                        ; grass outside the fence
.road:  ld a,(cur_y) : ld ixh,a : add a,a : add a,a : add a,ixh : xor l : ld ixh,a   ; dirt texture: scattered specks (pseudo-random per pixel)
        rlca : rlca : rlca : add a,ixh : ld ixh,a : rrca : rrca : xor l : add a,ixh : ld ixh,a : rlca : xor ixh : and 15
        cp 3 : ld a,2 : jr nc,.put
        ld a,(cur_y) : xor l : and 3 : add a,44 : cp 47 : jr c,.put : ld a,45
.put:   ld (de),a : inc de : inc l
        dec ixl : jp nz,.bit
        ld a,(bcnt) : dec a : ld (bcnt),a : jp nz,.byte
        jr .next
.blank: xor a : ld (de),a : ld h,d : ld l,e : inc de : ld bc,255 : ldir
.next:  ld a,(cur_y) : or a : jr z,.done
        dec a : ld (cur_y),a : jp .row
.done:  ret

solid_at:                                           ; D=y E=x -> carry if the car's base footprint (9x5 box) is off the track or touches a fence base line
        ld a,e : sub 4 : jr c,.solid : cp 248 : jr nc,.solid
        ld a,d : sub 2 : jr c,.solid : cp TRACK_H-4 : jr nc,.solid
        ld (sa_de),de
        ld hl,BANK_GROUND                           ; the four footprint corners must be on the road
        ld a,d : sub 2 : ld d,a : ld a,e : sub 4 : ld e,a : call bitat : jr nc,.solid
        ld a,e : add a,8 : ld e,a : call bitat : jr nc,.solid
        ld a,d : add a,4 : ld d,a : call bitat : jr nc,.solid
        ld a,e : sub 8 : ld e,a : call bitat : jr nc,.solid
        ld de,(sa_de) : ld hl,BANK_WALL             ; fence = only its base line, tested round the edge of the footprint
        ld a,d : sub 2 : ld d,a
        call .span : ret c
        ld c,3
.mid:   inc d
        ld a,e : sub 4 : ld e,a : call bitat : jr c,.hitm
        ld a,e : add a,8 : ld e,a : call bitat : jr c,.hitm
        ld a,e : sub 4 : ld e,a
        dec c : jr nz,.mid
        inc d
.span:  ld a,e : sub 4 : ld e,a : ld b,9
.sp:    call bitat : jr c,.hitm
        inc e : djnz .sp
        ld a,e : sub 5 : ld e,a
        or a : ret
.hitm:  scf : ret
.solid: scf
        ret
sa_de:  dw 0

bitat:                                              ; HL = plane, D = y, E = x -> carry = bit
        ld a,d : cp TRACK_H : jr c,.ok
        or a : ret
.ok:    push hl : push bc
        ld b,h : ld c,l
        ld l,d : ld h,0
        add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl
        add hl,bc
        ld a,e : srl a : srl a : srl a : ld c,a : ld b,0 : add hl,bc
        ld c,(hl)
        ld a,e : and 7 : ld b,a : inc b : ld a,c
.sh:    rlca : djnz .sh
        pop bc : pop hl
        ret


; ------------------------------------------------------------------- car
pc_reset:                                           ; fresh context in the player variables
        ld hl,pc_block : ld de,pc_block+1 : ld (hl),0 : ld bc,PCS-1 : ldir
        ld hl,$FFFF : ld (best_tenths),hl
        ld hl,-1000 : ld (sl_prev),hl
        ret

update_car:
        ld a,(skid) : or a : jr z,.s0
        dec a : ld (skid),a
.s0:    ld a,(cur_in) : ld c,a
        ld a,(boost_t) : or a : jr z,.bi             ; boost running: count it down
        dec a : ld (boost_t),a : jr nz,.bi
        ld a,1 : ld (hud_dirty),a
.bi:    bit BST,c : jr z,.bup
        ld a,(bst_prev) : or a : jr nz,.bdone
        ld a,1 : ld (bst_prev),a
        ld a,(boost_t) : or a : jr nz,.bdone
        ld a,(boost_cnt) : or a : jr z,.bdone        ; nothing stored
        dec a : ld (boost_cnt),a
        ld a,BOOST_FRAMES : ld (boost_t),a
        ld a,1 : ld (hud_dirty),a : jr .bdone
.bup:   xor a : ld (bst_prev),a
.bdone: ld a,(boost_t) : or a : jr z,.nbo           ; boost: surge forward even off the throttle
        ld a,(dir) : or a : jr nz,.nbo
        ld a,(speed) : add a,6 : jr nc,.bs
        ld a,255
.bs:    ld (speed),a
.nbo:
        ld a,(speed) : ld b,a
        bit BRK,c : jr nz,.brake
        bit DWN,c : jr nz,.down
        bit ACC,c : jr nz,.up
        ld a,b : or a : jr z,.nochg                 ; coast: half the old deceleration
        ld a,(steer_cnt) : and 1 : ld a,b : jr nz,.nochg
        dec a : jr .st
.brake: ld a,b : sub 4 : jr nc,.st                ; gentler braking
        xor a : jr .st
.down:  ld a,(dir) : or a : jr nz,.revacc
        ld a,b : or a : jr nz,.brake                ; still rolling forward -> brake
        ld a,1 : ld (dir),a : jr .nochg             ; stopped -> engage reverse
.revacc:
        ld a,b : add a,2 : cp REV_MAX : jr c,.st
        ld a,REV_MAX : jr .st
.up:    ld a,(dir) : or a : jr z,.fwd
        ld a,b : or a : jr nz,.brake                ; rolling backwards -> brake
        xor a : ld (dir),a : jr .nochg
.fwd:   ld a,b : add a,3 : jr nc,.st
        ld a,255
.st:    ld (speed),a
.nochg:
        ld hl,steer_cnt : inc (hl)
        ld a,(speed) : or a : jp z,.nosteer
        ld a,(blocked) : or a : jp nz,.nosteer      ; wedged against a fence: no turning on the spot, reverse out
        ld a,(speed) : cp 12 : jp c,.nosteer        ; no pivoting at a crawl
        ld b,15 : cp 28 : jr c,.rate                 ; turn rate grows with speed: very slow = a step every 16th frame
        ld b,7 : cp 60 : jr c,.rate
        ld b,3 : cp 110 : jr c,.rate
        ld b,1 : cp 170 : jr c,.rate
        ld b,3                                      ; near top speed: heavy steering again
.rate:  ld a,(steer_cnt) : and b : jp nz,.nosteer
        ld a,(dir) : or a : jr z,.nosw              ; reversing: left/right turn the nose the opposite way
        ld a,c : and %11110011 : ld e,a : bit LFT,c : jr z,.s1
        set RGT,e
.s1:    bit RGT,c : jr z,.s2
        set LFT,e
.s2:    ld c,e
.nosw:  ld a,(heading)
        bit LFT,c : jr z,.nl
        dec a : and NHEAD-1 : ld d,1 : jr .sth
.nl:    bit RGT,c : jr z,.rel
        inc a : and NHEAD-1 : ld d,2
.sth:   ld (heading),a
        ld a,(lastdir) : cp d : jr z,.same          ; count consecutive steps in one direction (11 degrees each)
        ld a,d : ld (lastdir),a : ld a,1 : ld (turn_run),a : jr .tr
.same:  ld a,(turn_run) : cp 200 : jr nc,.tr
        inc a : ld (turn_run),a
.tr:    ld a,(turn_run) : cp 3 : jr c,.nosteer      ; under about 30 degrees of turn: no skid, no scrub
        ld a,(speed) : ld hl,SURF_BLK : cp (hl) : jr c,.drag     ; at the skid speed of this surface (250 top speed, lower on dirt and ice) with the accelerator held, turning hard: tyres lose grip
        ld a,(dir) : or a : jr nz,.drag
        bit ACC,c : jr z,.drag
        ld a,14 : ld (skid),a
.drag:  ld a,(speed) : cp 128 : jr c,.nosteer       ; cornering resistance: every turn step scrubs some speed
        ld d,a : srl a : srl a : srl a : srl a : srl a : ld e,a : ld a,d : sub e : ld (speed),a
        jr .nosteer
.rel:   xor a : ld (turn_run),a : ld (lastdir),a
.nosteer:
        ld a,(speed) : or a : jr nz,.chase
        ld a,(heading) : ld (mov_head),a : jr .mh
.chase: ld a,(skid) : or a : jr z,.cf
        ld a,(steer_cnt) : and 7 : jr nz,.mh        ; skidding: travel direction lags the nose (slow catch-up = sideways slide)
.cf:    ld a,(heading) : ld b,a : ld a,(mov_head) : ld c,a
        ld a,b : sub c : and NHEAD-1 : jr z,.mh
        cp NHEAD/2 : ld a,c : jr nc,.dn
        inc a : jr .sm
.dn:    dec a
.sm:    and NHEAD-1 : ld (mov_head),a
.mh:    ld a,(mov_head) : ld b,a
        ld a,(dir) : or a : ld a,b : jr z,.fw
        add a,NHEAD/2 : and NHEAD-1
.fw:    ld (eff_h),a
        call speed_step
        call bst_mul
        ld (stp_dx),de : ld (stp_dy),bc
        ld hl,(car_x) : add hl,de : ld (new_x),hl
        ld hl,(car_y) : add hl,bc : ld (new_y),hl
        ld a,(new_y+1) : ld d,a
        ld a,(new_x+1) : ld e,a
        call solid_at
        jr c,.hit
        ld hl,(new_x) : ld (car_x),hl
        ld hl,(new_y) : ld (car_y),hl
        xor a : ld (blocked),a
        ret
.hit:   call snd_impact
        ld b,1                                      ; scrape: swing the travel direction away from the fence, nearest free angle first
.k:     push bc : ld a,(eff_h) : add a,b : and NHEAD-1 : call try_head : pop bc : jr nc,.ok
        push bc : ld a,(eff_h) : sub b : and NHEAD-1 : call try_head : pop bc : jr nc,.ok
        inc b : ld a,b : cp 8 : jr c,.k
        jr .dead                                    ; no way round within ~80 degrees: head-on
.ok:    xor a : ld (blocked),a
        ld a,(speed) : ld e,a : srl a : srl a : srl a : srl a : srl a : srl a : ld d,a   ; speed/64
        ld a,b : cp 5 : jr c,.lm
        ld a,e : srl a : srl a : srl a : srl a : add a,d : ld d,a   ; steep angle: extra drag
.lm:    ld a,b : ld c,a : xor a                     ; loss = (speed/64 + extra) * k : more angle, more drag
.ml:    add a,d : jr c,.cap
        dec c : jr nz,.ml
        ld d,a : ld a,e : sub d : jr nc,.sv
.cap:   xor a
.sv:    ld (speed),a
        ret

.dead:  ld a,1 : ld (blocked),a
        xor a : ld (skid),a
        ld a,(speed) : srl a : srl a : ld (speed),a
        ret

try_head:                                           ; A = heading -> moves the car there if free (carry clear), else carry set
        call step_for
        ld hl,(car_x) : add hl,de : ld (new_x),hl
        ld hl,(car_y) : add hl,bc : ld (new_y),hl
        ld a,(new_y+1) : ld d,a : ld a,(new_x+1) : ld e,a
        call solid_at : ret c
        ld hl,(new_x) : ld (car_x),hl
        ld hl,(new_y) : ld (car_y),hl
        or a : ret

step_for:                                           ; A = heading -> DE = dx, BC = dy (8.8) at the current speed level
        call speed_step
        call bst_mul
        ret

speed_step:                                         ; A = heading -> DE = dx, BC = dy (8.8) for the current speed level (unit vector table x level)
        ld l,a : ld h,0 : add hl,hl : add hl,hl : ld de,speed_u : add hl,de
        ld e,(hl) : inc hl : ld d,(hl) : inc hl : ld c,(hl) : inc hl : ld b,(hl)
        ld a,(speed) : rrca : rrca : rrca : rrca : and 15 : ld (ss_lv),a
        push bc
        call ss_mul : ld (ss_dx),hl
        pop de
        call ss_mul : ld b,h : ld c,l
        ld de,(ss_dx)
        ret
ss_mul:                                             ; HL = DE * level / 4 (signed)
        ld a,(ss_lv) : ld b,a : ld hl,0 : or a : jr z,.d
.l:     add hl,de : djnz .l
.d:     sra h : rr l : sra h : rr l
        ret
ss_lv:  db 0
ss_dx:  dw 0

bst_mul:                                            ; boost active: step vector DE,BC * 1.5
        ld a,(boost_t) : or a : ret z
        ld h,d : ld l,e : sra h : rr l : add hl,de : ex de,hl
        ld h,b : ld l,c : sra h : rr l : add hl,bc : ld b,h : ld c,l
        ret


; --- software car: restore the old rectangle from the clean copy, then draw with a fence depth test
restore_car:                                        ; copy the old car rectangle back from the clean image
        ld a,(old_valid) : or a : ret z
        ld a,(old_cx) : ld l,a : ld h,0 : ld de,-8 : add hl,de
        bit 7,h : jr z,.xs
        ld hl,0
.xs:    ld a,l : ld (dc_sx),a                       ; xs = max(cx-8,0)
        ld a,(old_cx) : add a,8 : ld e,a : ld a,0 : adc a,0 : ld d,a
        ld a,d : or a : jr nz,.clip
        ld a,e : ld b,a : ld a,(dc_sx) : ld c,a : ld a,b : sub c : jr .cnt
.clip:  xor a : ld hl,dc_sx : sub (hl)
.cnt:   ld (dc_cnt),a
        xor a : ld (dc_j),a : ld a,255 : ld (cur_win),a
.rj:    ld a,(old_cy) : ld b,a : ld a,(dc_j) : add a,b
        cp 8+12 : jr c,.next                        ; rows above the HUD are never drawn
        sub 12 : cp 192 : jr nc,.next
        ld b,a : rlca : rlca : and 3 : ld c,a
        ld a,(cur_win) : cp c : jr z,.same
        ld a,c : ld (cur_win),a : add a,a : ld e,a
        add a,18 : nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld a,e : add a,CLEAN_PG : nextreg REG_MMU2,a : inc a : nextreg REG_MMU3,a
.same:  ld a,b : and 63 : ld d,a
        ld a,(dc_sx) : ld e,a : ld l,a : ld a,d : add a,$40 : ld h,a
        ld a,(dc_cnt) : ld c,a : ld b,0
        ldir
.next:  ld a,(dc_j) : inc a : ld (dc_j),a : cp 16 : jr c,.rj
        ret
dc_cnt: db 0
cur_win: db 0

; --- software car with a fence depth test.
; Per car and frame we build, for each of its 16 rows, a 16-bit mask of the columns that lie BEHIND a fence
; (the first fence base line at or below that row, within the fence height, is lower than the car's ground
; row).  Those pixels are only drawn on the chain-link holes.  Rows without any fence nearby take a fast loop.
draw_car:
        push ix
        ld a,(car_x+1) : ld (car_cx),a : ld (old_cx),a
        ld a,(car_y+1) : ld (car_cy),a : ld (old_cy),a
        ld a,1 : ld (old_valid),a
        ld a,(heading) : ld l,a : ld h,0                                      ; unpack this heading's nibbles (80 bytes) into car_buf: 10 rows of 16
        add hl,hl : add hl,hl : add hl,hl : add hl,hl : ld d,h : ld e,l
        add hl,hl : add hl,hl : add hl,de : ld de,car_pat : add hl,de
        ld de,car_buf : ld b,80
        nextreg REG_MMU6,LOGO_PG                                              ; the car patterns live in their own page, at $C000
.up:    ld a,(hl) : inc hl : ld c,a : rrca : rrca : rrca : rrca : and 15 : ld (de),a : inc de
        ld a,c : and 15 : ld (de),a : inc de : djnz .up
        call map_track                                                        ; track bank back
        ld hl,car_buf-80 : ld (patp),hl                                       ; rows 5..14 only are stored
        ld a,(car_col) : add a,a : add a,a : add a,15 : ld c,a               ; colour LUT: pattern value -> palette index
        ld hl,dc_lut : xor a : ld (hl),a : inc hl
        ld a,c : inc a : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl
        ld a,8 : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl : inc a : ld (hl),a
        ld a,(car_cx)                                ; horizontal clipping: first column, first pattern column, count
        ld b,0 : ld c,16
        cp 8 : jr nc,.c1
        ld b,8 : sub b : neg : ld b,a : ld a,16 : sub b : ld c,a : xor a : jr .c3   ; cx<8: skip 8-cx columns, start at x=0
.c1:    cp 248 : jr c,.c2
        ld c,a : ld a,8 : add a,0 : ld a,c : sub 8 : ld (dc_sx0),a : ld a,c : cpl : add a,9 : ld c,a : jr .c4
.c2:    sub 8
.c3:    ld (dc_sx0),a
.c4:    ld a,b : ld (dc_i0),a : ld a,c : ld (dc_n),a
        call build_masks
        xor a : ld (dc_j),a
.rj:    ld a,(dc_j) : sub 5 : cp 10 : jp nc,.nextrow            ; pattern rows outside 5..14 are empty
        ld a,(car_cy) : ld b,a : ld a,(dc_j) : add a,b
        cp 8+12 : jp c,.nextrow
        sub 12 : cp 192 : jp nc,.nextrow
        ld (dc_sy),a : ld c,a
        ld a,(dc_any) : or a : jr z,.nm
        ld a,(dc_j) : add a,a : ld e,a : ld d,0 : ld hl,dc_mk : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ld (dc_m),de
.nm:    ld a,(dc_sx0) : ld e,a
        ld a,c : call l2_row_addr
        ld h,d : ld l,e                              ; HL = screen pointer
        ld a,c : and 1 : ld ixl,a
        ld a,(dc_n) : ld ixh,a
        ld a,(dc_j) : swapnib : ld e,a : ld d,0
        push hl : ld hl,(patp) : add hl,de : ld a,(dc_i0) : ld e,a : ld d,0 : add hl,de : ex de,hl : pop hl   ; DE = pattern pointer
        ld b,high dc_lut
        ld a,(dc_any) : or a : jr z,.fast
        exx : ld hl,(dc_m) : exx
.px:    exx : add hl,hl : exx
        ld a,(de) : inc de
        jr c,.hid
        or a : jr z,.nx
        ld c,a : ld a,(bc) : ld (hl),a
.nx:    inc l : dec ixh : jr nz,.px
        jr .nextrow
.hid:   or a : jr z,.nx
        ld c,a : ld a,l : xor ixl : rra : jr c,.nx
        ld a,(bc) : ld (hl),a
        jr .nx
.fast:  ld a,(de) : inc de : or a : jr z,.fn
        ld c,a : ld a,(bc) : ld (hl),a
.fn:    inc l : dec ixh : jr nz,.fast
.nextrow:
        ld a,(dc_j) : inc a : ld (dc_j),a : cp 16 : jp c,.rj
        pop ix
        ret

build_masks:                                        ; fills dc_mk[16] and dc_any
        xor a : ld (dc_any),a
        ld a,(car_cx) : cp 8 : ret c : cp 248 : ret nc
        sub 8 : ld b,a : rrca : rrca : rrca : and 31 : ld (dc_bx),a
        ld a,(car_cy) : sub 12 : jr nc,.q1
        xor a
.q1:    ld c,a : ld a,(car_cy) : add a,9 : cp 192 : jr c,.q2
        ld a,191
.q2:    sub c : inc a : ld e,a                       ; rows to scan
        ld l,c : ld h,0 : add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl
        ld bc,BANK_WALL : add hl,bc : ld a,(dc_bx) : ld c,a : ld b,0 : add hl,bc
        ld bc,32 : xor a : ld d,a
.qs:    or (hl) : inc hl : or (hl) : inc hl : or (hl)
        add hl,bc : dec hl : dec hl
        dec e : jr nz,.qs
        or a : ret z                                 ; no fence near this car: nothing to hide behind
        ld a,(car_cx) : sub 8 : and 7 : ld e,0 : ld d,0 : ld hl,pow2 : ld e,a : add hl,de : ld a,(hl) : ld (mm),a
        xor a : ld (dc_i),a
.bi:    ld a,(car_cy) : ld b,a : ld a,(dc_i) : add a,b : sub 12                 ; k = cy-12+i
        jr c,.zero
        cp 192 : jr nc,.zero
        ld l,a : ld h,0 : add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl
        ld de,BANK_WALL : add hl,de
        ld a,(dc_bx) : ld e,a : ld d,0 : add hl,de
        call win16
        jr .st
.zero:  ld hl,0
.st:    ld a,h : or l : jr z,.nz
        ld a,1 : ld (dc_any),a
.nz:    ld a,(dc_i) : add a,a : ld e,a : ld d,0 : push hl : ld hl,dc_b : add hl,de : pop de : ld (hl),e : inc hl : ld (hl),d
        ld a,(dc_i) : inc a : ld (dc_i),a : cp 21 : jr c,.bi
        ld a,(dc_any) : or a : ret z
        xor a : ld (dc_j2),a
.mj:    ld a,(dc_j2) : ld b,a                       ; front = bases at rows j..min(j+5,12) (at or above the car's ground row)
        add a,5 : cp 13 : jr c,.f1
        ld a,12
.f1:    ld c,a : cp b : jr c,.nofront
        call or_range : jr .gf
.nofront: ld hl,0
.gf:    push hl
        ld a,(dc_j2) : ld b,a : add a,5 : ld c,a    ; behind = bases at rows max(j,13)..j+5 (below the car's ground row)
        ld a,b : cp 13 : jr nc,.b1
        ld b,13
.b1:    ld a,c : cp b : jr c,.nobehind
        call or_range : jr .gb
.nobehind: ld hl,0
.gb:    pop de
        ld a,d : cpl : and h : ld h,a : ld a,e : cpl : and l : ld l,a
        ld a,(dc_j2) : add a,a : ld e,a : ld d,0 : push hl : ld hl,dc_mk : add hl,de : pop de : ld (hl),e : inc hl : ld (hl),d
        ld a,(dc_j2) : inc a : ld (dc_j2),a : cp 16 : jr c,.mj
        ret

or_range:                                           ; OR of dc_b[B..C] (inclusive) -> HL
        ld a,b : add a,a : ld e,a : ld d,0 : ld hl,dc_b : add hl,de
        ld a,c : sub b : inc a : ld b,a
        ld de,0
.l:     ld a,(hl) : inc hl : or e : ld e,a : ld a,(hl) : inc hl : or d : ld d,a : djnz .l
        ex de,hl : ret

win16:                                              ; HL -> three plane bytes; returns the 16 bits starting (mm)-shifted: HL
        ld a,(mm) : ld c,a
        ld a,(hl) : inc hl : ld d,a : ld e,c : mul d,e : ld b,e
        ld a,(hl) : inc hl : ld d,a : ld e,c : mul d,e : push de
        ld a,(hl) : ld d,a : ld e,c : mul d,e : ld a,d
        pop hl
        add a,l : ld l,a : jr nc,.n
        inc h
.n:     ld a,h : add a,b : ld h,a
        ret

dc_any: db 0
dc_bx:  db 0
dc_i0:  db 0
dc_n:   db 16
dc_sx0: db 0
dc_j2:  db 0
mm:     db 1
dc_m:   dw 0
dc_mk:  ds 32
dc_b:   ds 42
pow2:   db 1,2,4,8,16,32,64,128

; ------------------------------------------------------------ lap timing
update_lap:
        ld a,(car_y+1) : srl a : srl a : ld b,a
        ld a,(car_x+1) : srl a : srl a : ld c,a
        ld l,b : ld h,0
        add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl
        ld e,c : ld d,0 : add hl,de
        ld de,BANK_PROG : add hl,de
        ld a,(hl) : cp 255 : jr z,.cross
        ld (lastp),a                                ; progress (for the race order)
.cross: call hum_chain                              ; keep the ordered-gate counter up to date
        call line_cross : ret nc
        ld a,(npts) : ld b,a : srl b : srl b : sub b : ld c,a    ; C = 3/4 of the gates
        ld a,(gate) : cp c : jr c,.early
        xor a : ld (gate),a                         ; all the gates driven through in order, then the line: a lap
        jp lap_complete
.early: ld b,a : ld a,(npts) : srl a : srl a : srl a : ld c,a : ld a,b : cp c : ret nc    ; gate 1/8 or more: the track merely passes over the line mid-lap - nothing happens
        xor a : ld (gate),a : jp lap_reset          ; the start of the race: the line only restarts the timing

hum_chain:                                          ; GATE = the furthest lane waypoint reached in order (0 at the line, never wraps); any lane position counts, a waypoint is "reached" within GATE_R of it
        ld b,3
.s:     push bc
        ld a,(gate) : inc a : ld hl,npts : cp (hl) : jr nc,.pv     ; no gate after the last
        call hdist : cp GATE_R : jr nc,.pv
        ld hl,gate : inc (hl) : pop bc : djnz .s : ret
.pv:    ld a,(gate) : or a : jr z,.dn
        call hdist : cp GATE_R : jr c,.dn                          ; still within reach of the current gate
        ld a,(gate) : dec a : call hdist : cp GATE_R : jr nc,.dn   ; the gate behind is near: driving backwards
        ld hl,gate : dec (hl) : pop bc : djnz .s : ret
.dn:    pop bc : ret
GATE_R      equ 80
hdist:                                              ; A = waypoint -> A = |dx| + 2|dy| from the car (saturating)
        call wp_at
        ld a,(car_x+1) : sub b : jr nc,.x : neg
.x:     ld d,a
        ld a,(car_y+1) : sub c : jr nc,.y : neg
.y:     add a,a : jr c,.sat
        add a,d : ret nc
.sat:   ld a,255 : ret

line_cross:                                         ; carry = the car has just crossed the drawn start line in the direction of travel
        ld a,(car_x+1) : ld l,a : ld h,0 : ld a,(sl_cx) : ld e,a : ld d,0 : or a : sbc hl,de : ld (lc_u),hl
        ld a,(car_y+1) : ld l,a : ld h,0 : ld a,(sl_cy) : ld e,a : ld d,0 : or a : sbc hl,de : add hl,hl : ld (lc_w),hl
        ld de,(lc_u) : ld a,(sl_ax) : call mulc : push hl
        ld de,(lc_w) : ld a,(sl_ay) : call mulc : pop de : add hl,de
        push hl                                     ; HL = distance along the direction of travel from the line
        ld de,(lc_w) : ld a,(sl_ax) : call mulc : push hl
        ld de,(lc_u) : ld a,(sl_ay) : call mulc : pop de : ex de,hl : or a : sbc hl,de     ; across the line = ax*w - ay*u
        bit 7,h : jr z,.pa                          ; |across|
        xor a : sub l : ld l,a : ld a,0 : sbc a,h : ld h,a
.pa:    ld de,(sl_lim) : or a : sbc hl,de : ld a,0 : rla : xor 1 : ld c,a   ; C=1 when beyond the ends of the line
        pop hl
        ld de,(sl_prev) : ld (sl_prev),hl
        bit 7,d : jr z,.no                          ; was already past the line
        bit 7,h : jr nz,.no                         ; still before it
        ld a,c : or a : jr nz,.no
        ld a,1 : ld (lc_hit),a
        scf : ret
.no:    or a : ret
mulc:                                               ; HL = DE * A (A signed, |A| <= 4)
        push bc
        ld hl,0 : or a : jr z,.o
        bit 7,a : jr nz,.ng
        ld b,a
.p:     add hl,de : djnz .p
        jr .o
.ng:    neg : ld b,a
.m:     or a : sbc hl,de : djnz .m
.o:     pop bc
        ret
lc_u: dw 0
lc_w: dw 0

lap_complete:
        ld hl,(lap_tenths) : ld de,1000 : or a : sbc hl,de : ret c  ; ignore laps < 10 s
        ld hl,laps_done : inc (hl)
        ld a,(hl) : call bell_chk
        ld hl,(lap_tenths) : call lap_flash
        ld a,(boost_cnt) : cp 3 : jr nc,.nb                         ; each finish-line crossing banks a boost (max 3)
        inc a : ld (boost_cnt),a
.nb:
        ld hl,(lap_tenths) : ld de,(best_tenths) : or a : sbc hl,de : jr nc,.nobest
        ld hl,(lap_tenths) : ld (best_tenths),hl
.nobest:
lap_reset:
        ld hl,0 : ld (lap_tenths),hl
        xor a : ld (fcnt),a
        inc a : ld (hud_dirty),a
        ret

tick_lap:                                           ; the human car's own lap clock: 2 hundredths of a second per frame (50 frames a second)
        ld hl,(lap_tenths) : inc hl : inc hl : ld (lap_tenths),hl
        ret

tick_time:                                          ; the practice countdown, once a second
        ld a,(gf) : inc a : cp 5 : jr nc,.t
        ld (gf),a : ret
.t:     xor a : ld (gf),a
        ld a,(cd_f) : inc a : cp 10 : jr nc,.s
        ld (cd_f),a : ret
.s:     xor a : ld (cd_f),a
        ld hl,(cd_s) : ld a,h : or l : ret z
        dec hl : ld (cd_s),hl
        ld a,1 : ld (hud_dirty),a
        ld a,h : or l : ret nz
        ld a,(phase) : or a : ret nz                ; practice: time up ends the session
        ld a,1 : ld (race_over),a
        ret
cd_f:   db 0
cd_s:   dw 180
gf:     db 0

; ------------------------------------------------------------------- HUD
hud_clear_old:
        ld ix,cpu_t : ld b,CPU_N
.l:     xor a : ld (ix+29),a : ld (ix+21),a : ld (ix+14),$0F : ld (ix+15),$27
        ld de,CPU_SZ : add ix,de : djnz .l
        ret
hud_static:
        xor a : ld (fr_x),a : ld (fr_y),a : ld (fr_c),a : ld a,255 : ld (fr_w),a : ld a,12 : ld (fr_h),a
        call fill_rect                               ; wipe the top bar: nothing of the last race stays behind
        ld a,1 : ld (hud_dirty),a
        jp hud_update

; top row: best laps in seconds for BLUE, RED, the practice countdown, GREEN, YELLOW
hud_update:
        ld a,(hud_dirty) : or a : ret z
        xor a : ld (hud_dirty),a
        ld ix,cpu_t : ld iy,hud_pos : ld b,CPU_N
.c:     push bc
        ld a,CPU_N : sub b : ld (hd_slot),a
        ld a,(ix+23) : or a : jr nz,.act
        ld a,(ix+29) : or a : jr z,.skip            ; finished the race: its place and a chequered flag
        push ix : call hud_place : pop ix : jr .skip
.act:   ld a,(phase) : or a : jr z,.pd
        ld a,(hd_slot) : ld e,a : ld d,0 : ld hl,rc_col : add hl,de : ld b,(hl) : dec b : jr .dd     ; race layout: dots, LAPS n
.pd:    ld b,(iy+1) : dec b
.dd:    ld a,(ix+21) : push ix : call draw_dots : pop ix      ; stored boosts: 1-3 white dots left of the time
        ld a,(phase) : or a : jr nz,.rc
        ld l,(ix+14) : ld h,(ix+15) : ld a,(iy+0) : ld b,(iy+1) : push ix : call hud_cell : pop ix
        jr .skip
.rc:    push ix : call hud_race : pop ix
.skip:  ld de,CPU_SZ : add ix,de : inc iy : inc iy
        pop bc : djnz .c
        ld a,(phase) : or a : jp nz,hud_posdraw
        ld a,3 : ld (txt_fg),a                       ; countdown m:ss
        ld a,14 : ld (txt_col),a : xor a : ld (txt_row),a
        ld hl,(cd_s) : ld c,'0'
.m:     ld de,60 : or a : sbc hl,de : jr c,.m2
        inc c : jr .m
.m2:    add hl,de : ld a,c : push hl : call print_char : pop hl
        ld a,':' : push hl : call print_char : pop hl
        ld de,10 : ld c,'0'
.t:     or a : sbc hl,de : jr c,.t2
        inc c : jr .t
.t2:    add hl,de : ld a,c : push hl : call print_char : pop hl
        ld a,l : add a,'0' : jp print_char

hud_pos: db 16,2, 24,8, 20,20, 28,26                ; text colour and column for each car slot

hud_place:                                          ; a finished car: "1ST" etc and a chequered flag where its LAPS counter was
        ld a,(ix+29) : dec a : add a,a : add a,a : add a,a : ld e,a : ld d,0 : ld hl,s_places : add hl,de
        ld a,(hd_slot) : ld e,a : ld d,0 : push hl : ld hl,rc_col : add hl,de : ld a,(hl) : pop hl
        ld (hd_c),a : ld (txt_col),a
        push hl : ld b,a : dec b : xor a : call draw_dots : pop hl                  ; boost dots off
        ld a,(iy+0) : ld (txt_fg),a : xor a : ld (txt_row),a
.s:     ld a,(hl) : or a : jr z,.f
        push hl : call print_char : pop hl : inc hl : jr .s
.f:     ld a,(hd_c) : add a,4 : ld b,a
draw_flag:                                          ; 8x8 chequered flag in text column B, top row
        ld a,b : add a,a : add a,a : add a,a : ld (dd_x),a
        xor a : ld (dd_r),a
.row:   ld a,(dd_x) : ld e,a : ld a,(dd_r) : call l2_row_addr
        ld a,(dd_r) : and 2 : ld c,a : ld b,8
.px:    ld a,8 : sub b : and 2 : xor c : jr z,.bk
        ld a,3 : jr .w
.bk:    xor a
.w:     ld (de),a : inc e : djnz .px
        ld hl,dd_r : inc (hl) : ld a,(hl) : cp 8 : jr c,.row
        ret
hd_c: db 0
s_places: db "1ST   ",0,0,"2ND   ",0,0,"3RD   ",0,0,"4TH   ",0,0

hud_race:                                           ; race: "LAPS n" (laps still to run) in the car's colour
        ld a,(laps_total) : sub (ix+24) : jr nc,.l
        xor a
.l:     ld (hd_laps),a
        ld a,(iy+0) : ld (txt_fg),a : xor a : ld (txt_row),a
        ld a,(hd_slot) : ld e,a : ld d,0 : ld hl,rc_col : add hl,de : ld a,(hl) : ld (txt_col),a
        ld hl,lap_show : add hl,de : ld a,(hl) : or a : jr z,.nl      ; just crossed the line: the lap time instead of LAPS n
        ld hl,lap_last : add hl,de : add hl,de : ld a,(hl) : inc hl : ld h,(hl) : ld l,a
        call print_tenths : ld a,' ' : jp print_char
.nl:    ld hl,s_laps
.s:     ld a,(hl) : or a : jr z,.d
        push hl : call print_char : pop hl : inc hl : jr .s
.d:     ld a,(hd_laps) : cp 10 : jr nc,.t
        push af : ld a,' ' : call print_char : pop af : add a,'0' : jp print_char
.t:     jp print_dec2
s_laps: db "LAPS",0
rc_col: db 1,9,17,25
hd_slot: db 0
hd_laps: db 0

hud_posdraw:                                        ; race: 1234 bottom left, in the colours of the cars holding those places
        xor a : ld (txt_col),a : ld a,23 : ld (txt_row),a
        ld a,(ro_n) : ld b,a : ld c,0
.l:     ld a,b : or a : ret z
        push bc
        ld a,c : ld e,a : ld d,0 : ld hl,pos_ord : add hl,de : ld e,(hl)
        ld hl,hud_pos : add hl,de : add hl,de : ld a,(hl) : ld (txt_fg),a
        pop bc : push bc
        ld a,c : add a,'1' : call print_char
        pop bc : inc c : djnz .l
        ret

draw_dots:                                          ; A = boosts (0..3), B = text column of the 8x8 cell to draw in
        ld e,a : ld d,0 : ld hl,dot_mask : add hl,de : ld a,(hl) : ld (dd_m),a
        ld a,b : add a,a : add a,a : add a,a : ld (dd_x),a
        xor a : ld (dd_r),a
.row:   ld a,(dd_x) : ld e,a : ld a,(dd_r) : call l2_row_addr
        ld a,(dd_m) : rlca : ld (dd_m),a : sbc a,a : and 3 : ld c,a
        ld h,d : ld l,e : ld b,8 : xor a
.z:     ld (hl),a : inc l : djnz .z
        ld a,e : add a,3 : ld l,a : ld h,d : ld (hl),c : inc l : ld (hl),c
        ld hl,dd_r : inc (hl) : ld a,(hl) : cp 8 : jr c,.row
        ret
dot_mask: db 0,%00011000,%01100110,%11011011
dd_m: db 0
dd_x: db 0
dd_r: db 0

hud_cell:                                           ; HL = tenths, A = colour, B = column
        ld (txt_fg),a : ld a,b : ld (txt_col),a : xor a : ld (txt_row),a
        ld de,10000 : push hl : or a : sbc hl,de : pop hl : jr c,print_tenths
        ld hl,9999
print_tenths:                                       ; HL = hundredths of a second 0..9999 -> "SS.TT" drawn at txt_col/txt_row
        ld de,tbuf : call cs_fmt
        xor a : ld (de),a
        ld hl,tbuf : jp print_str
cs_fmt:                                             ; HL = 0..9999, DE = destination -> "SS.TT" (a blank for a leading zero); DE ends after it
        ld bc,1000 : call cf_dg : cp '0' : jr nz,.a
        ld a,' '
.a:     ld (de),a : inc de
        ld bc,100 : call cf_dg : ld (de),a : inc de
        ld a,'.' : ld (de),a : inc de
        ld bc,10 : call cf_dg : ld (de),a : inc de
        ld a,l : add a,'0' : ld (de),a : inc de
        ret
cf_dg:      ld a,'0'                                           ; HL / BC -> digit in A, remainder in HL
.l:     or a : sbc hl,bc : jr c,.d
        inc a : jr .l
.d:     add hl,bc : ret
tbuf:   ds 7

print_dec2:                                         ; A = 0..99
        ld b,0
.l:     cp 10 : jr c,.d
        sub 10 : inc b : jr .l
.d:     push af
        ld a,b : add a,'0' : call print_char
        pop af : add a,'0'
        jp print_char

print_at:                                           ; B=col C=row HL=string (0-terminated)
        ld a,b : ld (txt_col),a
        ld a,c : ld (txt_row),a
.l:     ld a,(hl) : or a : ret z
        push hl : call print_char : pop hl
        inc hl : jr .l

        MACRO GLYPHBIT
        rlc c
        sbc a,a
        and h
        ld (de),a
        inc e
        ENDM

print_char:                                         ; A = ASCII, draws at txt_col/txt_row
        sub 32 : jr c,.sp
        cp 83 : jr nz,.ns : ld a,63                     ; lower case s -> the small s drawn in the '_' slot
.ns:
        cp 64 : jr c,.ok
.sp:    xor a
.ok:    ld l,a : ld h,0 : add hl,hl : add hl,hl : add hl,hl
        ld de,font : add hl,de : push hl : pop ix
        ld a,(txt_row) : ld b,a
        rrca : rrca : rrca : and 3 : add a,a
pc_pg:  add a,18                                    ; (the operand is patched to draw into the clean-copy pages)
        nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld a,b : and 7 : add a,a : add a,a : add a,a : ld d,a
        ld a,(txt_col) : add a,a : add a,a : add a,a : ld e,a
        ld a,(txt_fg) : ld h,a
        ld b,8
.row:   ld c,(ix+0)
        GLYPHBIT
        GLYPHBIT
        GLYPHBIT
        GLYPHBIT
        GLYPHBIT
        GLYPHBIT
        GLYPHBIT
        GLYPHBIT
        ld a,e : sub 8 : ld e,a
        inc d : inc ix : djnz .row
        ld hl,txt_col : inc (hl)
        ret

; number board: white frame, black face, the track number, on a short post (corner chosen per track)
fill_rect:                                          ; fr_x fr_y fr_w fr_h fr_c
.row:   ld a,(fr_x) : ld e,a : ld a,(fr_y) : call l2_row_addr
        ld a,(fr_c) : ld b,a : ld a,(fr_w) : ld c,a : ld a,b
.p:     ld (de),a : inc e : dec c : jr nz,.p
        ld hl,fr_y : inc (hl)
        ld hl,fr_h : dec (hl) : jr nz,.row
        ret

draw_board:
        ld hl,(meta_ptr) : ld de,9 : add hl,de
        ld a,(hl) : ld (bd_col),a : inc hl : ld a,(hl) : ld (bd_row),a
        ld a,(bd_col) : add a,a : add a,a : add a,a : ld (bd_px),a
        ld a,(bd_row) : add a,a : add a,a : add a,a : ld (bd_py),a
        ld a,(bd_px) : ld (fr_x),a : ld a,(bd_py) : dec a : ld (fr_y),a
        ld a,32 : ld (fr_w),a : ld a,10 : ld (fr_h),a : ld a,3 : ld (fr_c),a : call fill_rect
        ld a,(bd_px) : inc a : ld (fr_x),a : ld a,(bd_py) : ld (fr_y),a
        ld a,30 : ld (fr_w),a : ld a,8 : ld (fr_h),a : xor a : ld (fr_c),a : call fill_rect
        ld a,(bd_px) : add a,15 : ld (fr_x),a : ld a,(bd_py) : add a,9 : ld (fr_y),a
        ld a,2 : ld (fr_w),a : ld a,5 : ld (fr_h),a : ld a,3 : ld (fr_c),a : call fill_rect
        ld a,3 : ld (txt_fg),a
        ld a,(bd_col) : inc a : ld (txt_col),a
        ld a,(bd_row) : ld (txt_row),a
        ld a,(track_idx) : inc a
        jp print_dec2

; start/finish line: a black-and-white chequered strip across the road, a little ahead of the start position,
; running at 90 degrees to the direction of travel (marched out each way until the fence or the road edge)
draw_best:                                          ; bottom-right corner: L BEST (local) / O BEST (online) ss.tS, swapped every 5 seconds
        ld a,6 : ld (bt_f),a
        jp hs_binit
best_tick:                                          ; once per frame
        ld hl,bt_f : dec (hl) : ret nz
        ld (hl),6
        jp hs_bflip
bt_f:   db 6

draw_startline:
        ld hl,(meta_ptr) : ld a,(hl) : ld (sl_x+1),a : inc hl : ld a,(hl) : ld (sl_y+1),a : inc hl : ld a,(hl)
        and $F8 : add a,4 : and 31 : ld (sl_h),a      ; snap the travel direction to the nearest isometric axis (the fences run along these)
        ld hl,hcos : ld (slc_p),hl : ld hl,hsin : ld (sls_p),hl
        ld a,(track_idx) : sub 4 : cp 3 : jr nc,.std
        ld hl,hcos5 : ld (slc_p),hl : ld hl,hsin5 : ld (sls_p),hl      ; tracks 5, 6: fences at -14.8 / 75.2 degrees
        ld a,31 : ld (sl_h),a
.std:
        ld a,(track_idx) : sub 7 : cp 18 : jr nc,.nf         ; tracks 8 to 24: start-line heading from a table
        ld e,a : ld d,0 : ld hl,slh_t : add hl,de : ld a,(hl) : ld (sl_h),a
.nf:
        ld a,$80 : ld (sl_x),a : ld (sl_y),a
        ld a,(sl_h) : call sl_vec
        ld b,16
.f:     call sl_adv : djnz .f
        ld hl,(sl_x) : ld (sl_x0),hl : ld hl,(sl_y) : ld (sl_y0),hl
        ld a,(sl_x0+1) : ld (sl_cx),a : ld a,(sl_y0+1) : ld (sl_cy),a
        ld a,(sl_h) : cp 16 : sbc a,a : cpl : ld (sl_ns),a
        ld a,(sl_h) : sub 8 : and 31 : cp 16 : sbc a,a : ld (sl_nc),a
        ld a,(sl_nc) : or 1 : ld (sl_ax),a : ld a,(sl_ns) : or 1 : ld (sl_ay),a : ld hl,100 : ld (sl_lim),hl
        ld a,(track_idx) : sub 4 : cp 3 : jr nc,.nl5
        ld a,4 : ld (sl_ax),a : ld a,-1 : ld (sl_ay),a : ld hl,290 : ld (sl_lim),hl
.nl5:
        ld a,(track_idx) : sub 7 : cp 18 : jr nc,.nl8
        ld e,a : ld d,0 : add a,a : add a,e : ld e,a : ld hl,slax_t : add hl,de      ; 3 bytes a track: ax, ay, limit
        ld a,(hl) : ld (sl_ax),a : inc hl : ld a,(hl) : ld (sl_ay),a : inc hl : ld a,(hl) : ld l,a : ld h,0 : ld (sl_lim),hl
.nl8:
        ld hl,-1000 : ld (sl_prev),hl : xor a : ld (lap_armed),a
        ld (gc_ok),a
        ld a,(sl_h) : add a,8 : and 31 : call sl_ray
        ld a,(sl_h) : sub 8 : and 31
sl_ray:                                             ; A = heading to march along from the centre point; ends with a pole + light
        call sl_vec
        ld hl,(sl_x0) : ld (sl_x),hl : ld hl,(sl_y0) : ld (sl_y),hl
        ld a,(sl_x0+1) : ld (sl_lx),a : ld a,(sl_y0+1) : ld (sl_ly),a
        ld b,90
.l:     call sl_adv
        ld a,(sl_y+1) : ld d,a : ld a,(sl_x+1) : ld e,a
        ld hl,BANK_GROUND : call bitat : jr nc,.end
        ld hl,BANK_WALL : call bitat : jr c,.end
        call sl_plot
        ld a,(sl_x+1) : ld (sl_lx),a : ld a,(sl_y+1) : ld (sl_ly),a
        djnz .l
.end:   ld hl,sl_tab                                ; pole with a purple round light on top, standing at the end of the line
draw_tab:                                           ; HL = (dy,dx,count,colour)* $7F table, origin sl_lx,sl_ly
.e:     ld a,(hl) : cp $7F : ret z
        ld a,(sl_ly) : add a,(hl) : ld (sl_qy),a : inc hl
        ld a,(sl_lx) : add a,(hl) : ld (sl_qx),a : inc hl
        ld b,(hl) : inc hl : ld a,(hl) : inc hl : ld (sl_col),a
.p:     push hl : push bc : call sl_px : pop bc : pop hl
        ld a,(sl_qx) : inc a : ld (sl_qx),a : djnz .p
        jr .e
sl_px:                                              ; plot sl_col at (sl_qx,sl_qy) if it is on the playfield
        ld a,(sl_qy) : cp 9 : ret c : cp 192 : ret nc
        ld a,(sl_qx) : ld e,a : ld a,(sl_qy) : call l2_row_addr
        ld a,(sl_col) : ld (de),a
        ret
sl_tab: db -1,0,1,3, -2,0,1,3, -3,0,1,3, -4,0,1,3, -5,0,1,3, -6,0,1,3, -7,0,1,3, -8,0,1,3, -9,0,1,3
        db -13,-1,3,14, -12,-2,5,14, -11,-2,5,14, -10,-1,3,14, -12,-1,1,15, $7F
slh_t:  db 0,24,16,16,0,0, 20,20,20, 0,0,0, 16,20,20, 0,0, 0                                  ; start-line heading: tracks 8 (east), 9 (north), 10, 11 (west), 12, 13 (east)
slax_t: db 1,0,100, 0,-1,50, -1,0,100, -1,0,100, 1,0,100, 1,0,100
        db -1,-1,100, -1,-1,100, -1,-1,100, 1,0,100, 1,0,100, 1,0,100, -1,0,100, -1,-1,100, -1,-1,100, 1,0,100, 1,0,100, 1,0,100
sl_lx: db 0
sl_cx: db 0
sl_cy: db 0
sl_ns: db 0
sl_nc: db 0
sl_ly: db 0
sl_qx: db 0
sl_qy: db 0
sl_col: db 0
sl_plot:
        ld a,(sl_y+1) : ld (sl_py),a
        ld c,2
.r:     ld a,(sl_x+1) : ld e,a : ld a,(sl_py) : call l2_row_addr
        ld a,(sl_x+1) : srl a : ld hl,sl_py : add a,(hl) : and 1 : jr z,.blk
        ld a,3 : jr .w
.blk:   xor a
.w:     ld (de),a
        ld hl,sl_py : inc (hl)
        dec c : jr nz,.r
        ret
sl_vec:                                             ; A = heading -> sl_dx = 2*cos (8.8), sl_dy = sin/2 on screen
        ld e,a : ld d,0
        ld hl,(slc_p) : add hl,de : ld a,(hl) : ld l,a : add a,a : sbc a,a : ld h,a : add hl,hl : ld (sl_dx),hl
        ld hl,(sls_p) : add hl,de : ld a,(hl) : ld l,a : add a,a : sbc a,a : ld h,a : ld (sl_dy),hl
        ret
sl_adv:
        ld hl,(sl_x) : ld de,(sl_dx) : add hl,de : ld (sl_x),hl
        ld hl,(sl_y) : ld de,(sl_dy) : add hl,de : ld (sl_y),hl
        ret
sl_x: dw 0
sl_y: dw 0
sl_x0: dw 0
sl_y0: dw 0
sl_dx: dw 0
sl_dy: dw 0
sl_h: db 0
slc_p: dw hcos
sls_p: dw hsin
sl_ax: db 1                                         ; direction of travel across the line as small integers (game x, 2*screen y): diagonal 1,1 / track 5 (4,-1)
sl_ay: db 1
sl_lim: dw 100
sl_py: db 0

; basic trees on the grass: pseudo-random spots (fixed per track), only where a whole 6x9 patch is plain grass
draw_trees:
        ld a,(track_idx) : add a,a : add a,a : add a,11 : ld (tr_x),a : add a,a : inc a : ld (tr_y),a
        ld a,220 : ld (tr_n),a                     ; twice as many tries as before = twice the trees
.t:     ld a,(tr_x) : ld b,a : add a,a : add a,a : add a,b : add a,17 : ld (tr_x),a          ; x = x*5+17
        ld a,(tr_y) : ld b,a : add a,a : add a,a : add a,a : add a,b : add a,3 : ld (tr_y),a  ; y = y*9+3
        ld a,(tr_x) : cp 4 : jr c,.nx : cp 250 : jr nc,.nx
        ld (sl_lx),a
        ld a,(tr_y) : cp 18 : jr c,.nx : cp 190 : jr nc,.nx
        ld (sl_ly),a
        sub 9 : ld (tr_r),a : ld c,9                ; rows y-9 .. y-1
.r:     ld a,(sl_lx) : sub 2 : ld e,a : ld a,(tr_r) : call l2_row_addr
        ld b,6
.c:     ld a,(de) : cp GRASS : jr nz,.nx
        inc e : djnz .c
        ld hl,tr_r : inc (hl) : dec c : jr nz,.r
        ld a,(tr_n) : dec a : ld c,a                       ; this try's bit in the infield map (tools/surfaces.py): a tyre stack inside the track, the scenery of the surface outside
        srl a : srl a : srl a : ld e,a : ld d,0 : ld hl,SURF_INF : add hl,de
        ld a,c : and 7 : ld b,a : inc b : ld a,(hl)
.sh:    rrca : djnz .sh
        ld hl,SURF_TYRE : jr c,.go
        ld hl,SURF_OUT
.go:    call draw_tab
.nx:    ld a,(tr_n) : dec a : ld (tr_n),a : jp nz,.t
        ret
tr_x: db 0
tr_y: db 0
tr_n: db 0
tr_r: db 0

; other cars' engines on AY channel C: one car per frame in turn (not the lead human), each a little off the lead pitch
cpu_sound:
        ld b,CPU_N
.s:     ld a,(cs_k) : inc a : and 3 : ld (cs_k),a
        ld d,a : ld e,CPU_SZ : mul d,e : ld ix,cpu_t : add ix,de
        ld a,(ix+23) : or a : jr z,.nx
        push ix : pop hl : ld de,(snd_lead) : or a : sbc hl,de : jr nz,.go
.nx:    djnz .s
        jr .mute
.go:    ld a,(ix+5) : or a : jr z,.mute
        rrca : rrca : rrca : rrca : and 15
        ld l,a : ld h,0 : add hl,hl : add hl,hl : add hl,hl : ld d,h : ld e,l
        add hl,hl : add hl,hl : add hl,de            ; 40*level
        ex de,hl : ld hl,1100 : or a : sbc hl,de     ; same pitch law as the lead car
        ld d,h : ld e,l : srl d : rr e : srl d : rr e : srl d : rr e   ; period/8
        ld a,(cs_k) : or a : jr z,.d0
        dec a : jr z,.d1
        add hl,de : jr .dn                           ; third car: about 12% flatter
.d0:    srl d : rr e : add hl,de : jr .dn            ; first: about 6% flatter
.d1:    srl d : rr e : srl d : rr e : or a : sbc hl,de   ; second: about 3% sharper
.dn:    push hl : ld e,l : ld a,4 : call ay_write : pop hl : ld e,h : ld a,5 : call ay_write
        ld a,(ix+5) : rrca : rrca : rrca : rrca : and 15 : srl a : srl a : add a,4 : ld e,a
        ld a,10 : jp ay_write
.mute:  ld e,0 : ld a,10 : jp ay_write
cs_k:   db 0
snd_lead: dw 0

; ----------------------------------------------------------------- menu music (tools/mkmusic.py streams, 8K pages from MUS_PG; runs from the 50 Hz interrupt)
MUS_PG      equ 84
TITLE_PG    equ 24                                          ; the title picture, LZSS packed: pages 24-25 (free 8K pages below the 2 MB banks)
JING_PG     equ 92                                          ; the first-place jingle (page 92: track 25 owns 90-91)
MUS_WIN     equ $4000                                       ; the tune's page is borrowed into slot 2 for a moment each frame
mus_on:     db 0
mus_sv:     db 0
mus_pg:     db MUS_PG
mus_ptr:    dw MUS_WIN
mus_i:      db 0
mus_ch:     db 0                                            ; which AY chip (0-2) the interrupt is feeding

mus_resume:                                                 ; (re)start: put every register the tune owns back, then let the interrupt carry on where it was
        di
        im 2 : ld a,high mus_vec : ld i,a
        xor a : ld (mus_ch),a : ld hl,mus_sh
.c:     ld a,(mus_ch) : cpl : ld bc,PORT_AY_REG : out (c),a      ; $FF/$FE/$FD = AY 1/2/3
        ld d,0 : ld b,13
.r:     ld e,(hl) : inc hl
        ld a,d : push hl : push bc : call ay_write : pop bc : pop hl
        inc d : djnz .r
        ld de,3 : add hl,de
        ld a,(mus_ch) : inc a : ld (mus_ch),a : cp 3 : jr nz,.c
        ld a,$FF : ld bc,PORT_AY_REG : out (c),a            ; the sound effects live on AY 1
        ld a,1 : ld (mus_on),a
        ei
        ret

mus_off:                                                    ; race screen: interrupts off, silence the tune, the engine sound takes AY 1
        di
        xor a : ld (mus_on),a
        ld a,$FD : call mus_sil
        ld a,$FE : call mus_sil
        ld a,$FF : call mus_sil
        jp ay_init
mus_sil:ld bc,PORT_AY_REG : out (c),a
        ld e,0 : ld a,8 : call ay_write
        ld e,0 : ld a,9 : call ay_write
        ld e,0 : ld a,10 : jp ay_write

dbg_viz:    db 0
vj_on:      db 0                                            ; the first-place jingle is stepped from wait_frame while the race runs (interrupts off)
vz_car:     db 0                                            ; which colour the menu car shows (counts screen changes)
mus_isr:                                                    ; one 50 Hz frame of the tune (all three AY chips); leaves slot 2 and every register as it found them
        push af
        ld a,(mus_on) : or a : jr nz,.go
        pop af : ei : reti
.go:    push bc : push de : push hl
        ld bc,PORT_NEXTREG_SEL : ld a,REG_MMU2 : out (c),a : inc b : in a,(c)
        push af                                             ; the page that was in slot 2
.rd:    ld a,(mus_pg) : nextreg REG_MMU2,a
        ld hl,(mus_ptr)
        ld e,(hl) : inc hl : ld d,(hl) : inc hl
        bit 7,d : jr z,.nn
        ld a,(mus_pg) : inc a : ld (mus_pg),a
        ld hl,MUS_WIN : ld (mus_ptr),hl : jr .rd            ; this frame continues on the next page
.nn:    bit 6,d : jr z,.gv
        ld a,(mus_pg) : cp JING_PG : jr c,.lp
        xor a : ld (mus_on),a : ld (vj_on),a                ; the victory jingle is over: silence AY 2, the tune starts again from its top
        ld a,MUS_PG : ld (mus_pg),a : ld hl,MUS_WIN : ld (mus_ptr),hl
        ld a,$FE : call mus_sil
        jr .dn
.lp:    ld a,MUS_PG : ld (mus_pg),a
        ld hl,MUS_WIN : ld (mus_ptr),hl : jr .rd            ; end of the tune: round again
.gv:    xor a : ld (mus_ch),a
.cl:    ld a,(mus_ch) : cpl : ld bc,PORT_AY_REG : out (c),a
        xor a : ld (mus_i),a
.l:     srl d : rr e : jr nc,.n
        ld a,(hl) : inc hl
        ld b,a                                              ; B = value
        ld a,(mus_ch) : add a,a : add a,a : add a,a : add a,a
        ld c,a : ld a,(mus_i) : add a,c
        push hl : ld hl,mus_sh : add a,l : ld l,a : ld (hl),b : pop hl
        push de : ld a,(mus_i) : ld e,b : call ay_write : pop de
.n:     ld a,(mus_i) : inc a : ld (mus_i),a : cp 14 : jr nz,.l
        ld a,(mus_ch) : inc a : ld (mus_ch),a : cp 3 : jr z,.dn
        ld e,(hl) : inc hl : ld d,(hl) : inc hl             ; next chip's mask
        jr .cl
.dn:    ld (mus_ptr),hl
        ld a,$FF : ld bc,PORT_AY_REG : out (c),a            ; back to AY 1 for the effects
        pop af : nextreg REG_MMU2,a
        pop hl : pop de : pop bc : pop af
        ei : reti

; ----------------------------------------------------------------- sound
ay_write:                                           ; A = reg, E = value
        ld bc,PORT_AY_REG : out (c),a
        ld bc,PORT_AY_DAT : out (c),e
        ret

ay_init:
        ld a,7 : ld e,$32 : call ay_write           ; tone+noise on channel A, tone on C (other cars)
        ld a,6 : ld e,12  : call ay_write
        ld a,1 : ld e,0   : call ay_write
ay_silence:
        ld a,8 : ld e,0
        jp ay_write

sound_update:
        call sound_update0
        call snd_imp
        jp snd_bell

snd_impact:                                         ; any crash (fence or car): a short, quiet thud on channel B, only for a NEW contact:
        ld a,(snd_cn) : ld b,a : ld a,10 : ld (snd_cn),a      ; staying in contact (scraping a fence while accelerating) keeps re-arming the gap timer
        ld a,b : or a : ret nz
        ld a,(snd_hit) : or a : ret nz
        ld a,12 : ld (snd_hit),a
        ret
snd_imp:                                            ; 6 frames of noise on B (volume 9 down to 4), then 6 frames before it can sound again
        ld a,(snd_cn) : or a : jr z,.nc
        dec a : ld (snd_cn),a
.nc:    ld a,(snd_hit) : or a : ret z
        dec a : ld (snd_hit),a
        cp 6 : jr c,.fin
        push af : ld e,$22 : ld a,7 : call ay_write : ld e,20 : ld a,6 : call ay_write : pop af
        sub 2 : ld e,a : ld a,9 : jp ay_write
.fin:   cp 5 : ret nz
        ld e,12 : ld a,6 : jp ay_write
snd_hit:    db 0
bell_chk:                                           ; A = laps a car has just completed: the first car to start the final lap rings the bell
        ld b,a : ld a,(phase) : or a : ret z
        ld a,(bl_done) : or a : ret nz
        ld a,(laps_total) : dec a : cp b : ret nz
        ld a,1 : ld (bl_done),a : ld a,36 : ld (bl_t),a : xor a : ld (bl_p),a
        ret
snd_bell:                                           ; ding ding ding: three 12-frame rings on channel B, each fading out (overrides the impact / tyre noise while it rings)
        ld a,(bl_t) : or a : ret z
        dec a : ld (bl_t),a
        ld a,(bl_p) : ld (bl_b),a : inc a : cp 12 : jr c,.k
        xor a
.k:     ld (bl_p),a
        ld a,7 : ld e,$30 : call ay_write
        ld a,(bl_t) : and 1 : add a,a : add a,a : add a,90 : ld e,a : ld a,2 : call ay_write
        ld a,3 : ld e,0 : call ay_write
        ld a,(bl_b) : ld e,a : ld a,15 : sub e : ld e,a : ld a,9 : jp ay_write
bl_t:       db 0
bl_p:       db 0
bl_b:       db 0
bl_done:    db 0
snd_w:      db 0
snd_cn:     db 0                                    ; frames left before the next contact counts as a new crash

sound_update0:                                      ; lead human car: engine note + noise follows speed, tyre screech from any human
        ld a,(snd_skid) : or a : jr z,.ns
        dec a : ld (snd_skid),a
.ns:    ld hl,0 : ld (snd_lead),hl
        ld ix,cpu_t : ld b,CPU_N
.f:     ld a,(ix+23) : cp 1 : jr z,.got
        ld de,CPU_SZ : add ix,de : djnz .f
        ld a,8 : ld e,0 : call ay_write : jr .scr    ; no human car: channel A silent
.got:   ld (snd_lead),ix
        ld a,(ix+5) : ld e,0 : or a : jr z,.vol
        rrca : rrca : rrca : rrca : and 15 : srl a : srl a : add a,4 : ld e,a     ; quieter than before (was level/2 + 5)
.vol:   ld a,8 : call ay_write
        ld a,(ix+5) : rrca : rrca : rrca : rrca : and 15
        ld l,a : ld h,0
        add hl,hl : add hl,hl : add hl,hl                            ; 8*level
        ld d,h : ld e,l
        add hl,hl : add hl,hl                                        ; 32*level
        add hl,de                                                    ; 40*level
        ex de,hl : ld hl,1100 : or a : sbc hl,de                     ; period = 1100-40*level (about 100-220 Hz)
        ld a,(boost_t) : or a : jr z,.nbp                            ; boost: the engine note a little higher (period down by about 9%)
        ld d,h : ld e,l : srl d : rr e : srl d : rr e : srl d : rr e : srl d : rr e
        ld b,d : ld c,e : srl b : rr c : ex de,hl : add hl,bc : ex de,hl : or a : sbc hl,de
.nbp:   push hl
        ld e,l : xor a : call ay_write
        pop hl
        ld e,h : ld a,1 : call ay_write
.scr:   ld a,(snd_skid) : or a : jr z,.quiet               ; tyre screech: high wobbling tone on channel B
        ld a,7 : ld e,$20 : call ay_write                          ; tone + noise on B
        ld a,(snd_w) : inc a : ld (snd_w),a
        and 3 : add a,a : add a,a : add a,150 : ld e,a : ld a,2 : call ay_write      ; a lower note (period 150-162) with a small wobble (snd_w: own frame counter - fcnt belongs to the per-car context and is swapped every frame)
        ld a,3 : ld e,0 : call ay_write
        ld a,(snd_w) : and 15 : cp 5 : ld e,0 : jr c,.on                              ; sliding: a gap of 5 frames (a tenth of a second) in every 16, the squeal carries on in between
        ld e,9
.on:    ld a,9 : jp ay_write
.quiet: ld a,7 : ld e,$32 : call ay_write
        ld a,9 : ld e,0 : jp ay_write

; ------------------------------------------------------------------ input
        INCLUDE "src/input.asm"
        INCLUDE "src/menu.asm"
HS_PG       equ 80
HS_PGB      equ 93
hs_on:  nextreg REG_MMU7,HS_PG                      ; best-lap page (tables and online code) into $E000
        nextreg REG_MMU6,HS_PGB                     ; and the second page (name entry, panels, race-end choice) into $C000
        ret
hs_off: jp map_track                                ; slots 6/7 back to the current track
hs_init:        call hs_on : call pg_init : jp hs_off
hs_view:        call hs_on : call pg_view : jp hs_off
hs_best:        call hs_on : call pg_best : jp hs_off
hs_names:       call hs_on : call pg_names : jp hs_off
hs_choice:      call hs_on : call pg_choice : ld (nxt_flag),a : jp hs_off      ; map_track in hs_off clobbers A, so the answer goes to nxt_flag first
hs_logo:        call hs_on : call pg_logo : jp hs_off
title_show:     nextreg REG_MMU6,LOGO_PG : call pg_title : jp map_track   ; A = 0: show it and go on, A = 1: hold it for 10 s (page 81)
hs_quitq:       call hs_on : call pg_quit : ld (qt_res),a : jp hs_off
qt_res:         db 0
hs_ready:       call hs_on : call pg_ready : jp hs_off
hs_pause:       call hs_on : call pg_pause : jp hs_off
hs_pre:         call hs_on : call pg_pre : jp hs_off
hs_binit:       call hs_on : call pg_binit : jp hs_off
hs_bflip:       call hs_on : call pg_bflip : jp hs_off
hs_sync:        call hs_on : call pg_sync : jp hs_off
hs_pname:       call hs_on : call pg_pname : jp hs_off             ; A = car -> HL = its player name (pn_buf)
pn_buf:         ds 6
upd_flag:       db 0                                              ; 1 = the server has a newer build than this one
upd_msg:        db "UPDATE TO "
upd_ver:        ds 8                                              ; its build number (one string with upd_msg)
                db 0
upd_sel:        db "> UPDATE TO "                                 ; the same, selected
upd_sv:         ds 8
                db " <",0
mrows:          db 10                                             ; menu rows: 10, or 11 with the update item
hs_vcheck:      call mus_off                                     ; U on the main menu: ask the server for the newest build again
                ld a,1 : ld (ck_cen),a : call hs_on : call pg_vcheck : call hs_off : xor a : ld (ck_cen),a
                jp mus_resume
hs_update:      call mus_off                                     ; the tune stays off for the whole download (each slice used to stop and restart it)
                call hs_on : call pg_update : call hs_off
                jp mus_resume
hs_check_all:   call hs_on : call pg_check : push af : call hs_off : pop af : ret
nb:             ds 160                                           ; dot command line: must stay visible while the OS runs
hs_exec:        di : push af : ld a,(mus_on) : ld (mus_sv),a : xor a : ld (mus_on),a : pop af      ; the tune waits while the OS runs the dot command
                push hl : ld a,$FD : call mus_sil : ld a,$FE : call mus_sil : ld a,$FF : call mus_sil : pop hl      ; all nine tune channels and the effects go quiet
                nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF      ; M_EXECCMD (HL = command line): the OS memory layout back first,
                nextreg REG_MMU2,10 : nextreg REG_MMU3,11        ; kept in main memory so nothing paged out takes this code with it
                nextreg REG_MMU6,0 : nextreg REG_MMU7,1
                push hl : pop ix                                 ; M_EXECCMD wants the command line in IX
                rst 8 : db $8F
                xor a : out ($FE),a : nextreg $4A,0              ; the dot command leaves a white border: back to black
                di                                               ; the OS may leave interrupts on; here they would jump into screen memory
                nextreg REG_MMU7,HS_PG
                push af : ld a,(mus_sv) : or a : jr z,.nm
                call mus_resume                                  ; interrupt mode and vector back, tune carries on
.nm:            pop af
                ret

; ------------------------------------------------------------------ data
s_ver: db "26112011",0

; ---- everything one human car owns: this block is loaded from / stored to the car's context every frame
pc_block:
car_x:      dw 0
car_y:      dw 0
new_x:      dw 0
new_y:      dw 0
heading:    db 0
dir:        db 0
speed:      db 0
steer_cnt:  db 0
lastp:      db 0
fcnt:       db 0
lap_tenths: dw 0                                    ; the lap clock, in hundredths of a second
best_tenths: dw $FFFF
skid:       db 0
turn_run:   db 0
lastdir:    db 0
blocked:    db 0
mov_head:   db 0
stp_dx:     dw 0
stp_dy:     dw 0
eff_h:      db 0
boost_cnt:  db 0
boost_t:    db 0
bst_prev:   db 0
lap_armed:  db 0
sl_prev:    dw -1000
laps_done:  db 0
gate:       db 0                                    ; ordered gates: the lane waypoint reached by driving forwards this lap
pc_end:
PCS         equ pc_end-pc_block
hctx:       ds PCS*4                                ; one context per car
ctl:        db 0,6,6,6                              ; control choice per car: 0 KEMPSTON 1 KEMPSTON 2 2 INT2 L 3 INT2 R 4 CURSOR 5 KEYS 6 COMPUTER 7 UNWANTED
difficulty: db 1                                    ; 0 EASY 1 MEDIUM 2 HARD 3 EXPERT
laps_total: db 6
fr_cnt:     db 0
snd_skid:   db 0
race_over:  db 0
menu_sel:   db 0
track_idx:  db 0
trk_max:    db 13                                   ; tracks on offer: the finished ones (1 to 10); typing DEBUG on the instructions page unlocks all 25
prev_in:    db 0
laps_i:     db 3
txt_col:    db 0
txt_row:    db 0
txt_fg:     db 3
meta_ptr:   dw 0
cur_y:      db 0
win_pg:     db 0
wptr:       dw 0
gptr:       dw 0
bcnt:       db 0
hud_dirty:  db 0
car_col:    db 0
car_cx:     db 0
car_cy:     db 0
old_cx:     db 0
old_cy:     db 0
old_valid:  db 0
patp:       dw 0
dc_i:       db 0
dc_j:       db 0
dc_sx:      db 0
dc_sy:      db 0
fr_x:       db 0
fr_y:       db 0
fr_w:       db 0
fr_h:       db 0
fr_c:       db 0
bd_col:     db 0
bd_row:     db 0
bd_px:      db 0
bd_py:      db 0

            INCLUDE "build/pal.inc"
            INCLUDE "build/speed.inc"
            INCLUDE "build/hvec.inc"
cur_slot: db 0
lap_show: ds 4
lap_last: ds 8
wp_at:                                              ; A = waypoint -> B = x, C = y
        ld e,a : ld d,0
        ld hl,BANK_PATHX : add hl,de : ld b,(hl)
        ld hl,BANK_PATHY : add hl,de : ld c,(hl)
        ret
; ---- lap time flash: after a timed lap the car's LAPS counter shows the lap time for 3 seconds
lap_flash:                                          ; HL = lap time in tenths, for car cur_slot (keeps DE)
        push de : push hl
        ld a,(cur_slot) : ld e,a : ld d,0
        ld hl,lap_show : add hl,de : ld (hl),150
        ld hl,lap_last : add hl,de : add hl,de : pop de : ld (hl),e : inc hl : ld (hl),d
        pop de : ret
lap_tick:                                           ; once per frame; redraw the HUD when a flash runs out
        ld hl,lap_show : ld b,4
.l:     ld a,(hl) : or a : jr z,.n
        dec (hl) : jr nz,.n
        ld a,1 : ld (hud_dirty),a
.n:     inc hl : djnz .l
        ret
stack_area:
car_buf:    ds 160                                  ; fills the gap before the page-aligned colour table
            ds 40                                   ; stack room (SP starts at dc_lut and grows down through here, so keep it clear of car_buf)
            ALIGN 256
            ASSERT dc_lut-car_buf-160 >= 40, "stack would run into car_buf"
dc_lut:     ds 16                                   ; colour LUT: indexed as (high dc_lut):pattern value, so page aligned
            ASSERT (dc_lut & 255) == 0
            INCLUDE "src/cpu.asm"
code_end:
            ASSERT code_end <= $BA00                    ; the main code must stay below the IM2 vector table
            ORG $BA00
mus_vec:    ds 257,$BB                                  ; IM2 table: every vector points at $BBBB
            ORG $BBBB
            JP mus_isr
track_tab:
            INCLUDE "build/tracks.inc"                  ; per-track meta, parked behind the IM2 table to give the code room
upd_line:   ds 64                                       ; scratch for the high-score page (kept here to leave that page room for the track 25 table)
ud_fn:      ds 20
ud_sz:      ds 3
ud_buf:     ds 4
idle_go:    db 0                                        ; set by the page-81 timer: 20 s idle in the main menu
fr_ld:      ld de,fr_x : ld bc,5 : ldir : jp fill_rect       ; HL -> fr_x fr_y fr_w fr_h fr_c, then fill
ck_cen:     db 0                                        ; 1 = U pressed in the menu: centred panel covering the version line
ck_msg:     ld a,(ck_cen) : or a : jr z,.br
            ld hl,ck_t2 : call fr_ld : ld a,255 : ld (txt_fg),a : ld c,23 : ld hl,s_chk : jp print_cen
.br:        ld hl,ck_t : call fr_ld                          ; black panel, bottom right, with CHECKING FOR UPDATES...
            ld a,255 : ld (txt_fg),a : ld bc,$0917 : ld hl,s_chk : jp print_at
ck_t:       db 72,182,184,10,0
ck_t2:      db 24,182,208,10,0
            ALIGN 64
mus_sh:     ds 48                                           ; shadow of the registers the tune has written: 16 per chip (aligned so a slot never carries)
font:       INCBIN "build/font.bin"                     ; after the IM2 table and its jump (the code had grown into $BA00 and the font sat on the vectors)

; --------------------------------------------------- track banks (16K each)
            INCLUDE "src/trackdata.asm"

; --- best laps, file access and online scores live in the high-score page, which is mapped at $E000 while they run
            MMU 7, HS_PG
            ORG $EFC0                               ; the table (25 x 20 x 8 = 4000 bytes) + names + format marker end at $EFB4
            INCLUDE "src/hiscore.asm"
            ASSERT $ < $FFFF
            MMU 6, HS_PGB
            ORG $C000
            INCLUDE "src/hiscore_b.asm"
            ASSERT $ < $E000
            MMU 6, 81
            ORG $C000
            INCBIN "build/logo.bin"
            INCLUDE "src/insdata.asm"
car_pat:    INCBIN "build/cars.bin"
            INCLUDE "src/p81.asm"                   ; 32 headings x 80 bytes (the page holding the logo has room: main code was running past $BFFF)

            INCLUDE "build/music.inc"
            MMU 7, TITLE_PG
            ORG $E000
            INCBIN "build/title_a.lz"
            MMU 7, TITLE_PG+1
            ORG $E000
            INCBIN "build/title_b.lz"


            SAVENEX OPEN "stockcar.nex", start, dc_lut
            SAVENEX CORE 3,1,5
            SAVENEX CFG 0,0,0,0
            SAVENEX AUTO
            SAVENEX CLOSE
