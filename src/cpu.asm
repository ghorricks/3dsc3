; ===================================================================== CPU cars
; Each CPU car follows the lane centreline (waypoints in the track bank): it steers by the sign of the
; cross product between its heading and the direction to a point a few waypoints ahead, and slows for
; sharp turns.  State per car (CPU_SZ bytes, addressed through IX):
;  +0 X(8.8) +2 Y(8.8) +4 head +5 speed +6 waypoint +7 colour +8 old_cx +9 old_cy +10 old_valid
;  +11 top speed +12/13 lap frames +14/15 best lap (tenths of a second) +16 frame counter +17 sharp-turn flag
;  +18/19 start-line distance (previous frame) +20 lap armed +21 stored boosts (0..3) +22 boost frames left
;  +23 mode (0 off, 1 human, 2 computer) +24 laps done +25 control choice +26/27 pointer to the human context
        MACRO SWP g,o
        ld a,(g) : ld b,(ix+o) : ld (ix+o),a : ld a,b : ld (g),a
        ENDM

cpu_swap:                                           ; exchange the drawing globals with the car at IX
        SWP car_x,0
        SWP car_x+1,1
        SWP car_y,2
        SWP car_y+1,3
        SWP heading,4
        SWP car_col,7
        SWP old_cx,8
        SWP old_cy,9
        SWP old_valid,10
        SWP sl_prev,18
        SWP sl_prev+1,19
        SWP lap_armed,20
        ret

init_cpu:                                           ; set up the four cars from the menu (control choices) on the starting grid
        ld hl,(meta_ptr) : ld de,11 : add hl,de : ld a,(hl) : ld (npts),a
        ld ix,cpu_t : ld c,0
.k:     push bc
        push ix : pop hl : ld d,h : ld e,l : inc de : ld (hl),0 : ld bc,CPU_SZ-1 : ldir
        pop bc : push bc                              ; C = slot
        ld a,c : ld e,a : ld d,0
        ld hl,slot_col : add hl,de : ld a,(hl) : ld (ix+7),a
        ld hl,ctl : add hl,de : ld a,(hl) : ld (ix+25),a
        ld b,0                                        ; mode: 0 off, 1 human, 2 computer
        cp 7 : jr nc,.md
        ld b,1 : cp 6 : jr c,.md
        ld b,2
        ld a,(track_idx) : cp 25 : jr c,.md           ; lane paths exist for tracks 1 to 14
        ld b,0                                        ; no lane path on this track yet: the computer sits out
.md:    ld (ix+23),b
        ld (ix+14),$0F : ld (ix+15),$27 : ld (ix+18),$18 : ld (ix+19),$FC     ; best 99.9, line distance far behind
        ld a,b : or a : jp z,.nx
        call grid_pos
        ld a,(difficulty) : add a,a : add a,a : add a,c : ld e,a : ld d,0
        ld hl,cpu_caps : add hl,de : ld a,(hl) : ld (ix+11),a
        ld a,c : and 3 : ld e,a : ld d,0 : ld hl,cap_adj : add hl,de : ld a,(ix+11) : add a,(hl) : ld (ix+11),a
        ld a,(track_idx) : cp 1 : jr nz,.nt2          ; track 2 is longer in the original: slower computer cars
        ld a,(ix+11) : sub 24 : ld (ix+11),a
.nt2:   ld a,(difficulty) : cp 3 : jr nz,.nt3
        ld (ix+11),255                                ; EXPERT: every car as fast as the player
.nt3:   ld a,(ix+23) : cp 1 : jr z,.hum
        call nearest_wp : ld d,a                      ; computer car: first waypoint of its lane
        ld a,(npts) : srl a : cp d : ld a,d : jr nc,.fw
        xor a                                         ; a grid slot behind the line is nearest to the END of the lap path: it starts at waypoint 0, not by driving the loop backwards
.fw:    ld (ix+6),a
        jr .nx
.hum:   pop bc : push bc                              ; C = slot again (grid_pos etc. changed it: the cars all shared one context!)
        ld a,c : ld d,a : ld e,PCS : mul d,e : ld hl,hctx : add hl,de : ld (ix+26),l : ld (ix+27),h
        call pc_reset
        ld a,(ix+4) : ld (heading),a : ld (mov_head),a
        ld l,(ix+26) : ld h,(ix+27) : ex de,hl : ld hl,pc_block : ld bc,PCS : ldir
.nx:    ld de,CPU_SZ : add ix,de
        pop bc : inc c : ld a,c : cp CPU_N : jp c,.k
        ret

grid_centre:                                        ; the start point can sit near one fence: find the middle of the road across the line (once per race)
        ld a,(gc_ok) : or a : ret nz
        inc a : ld (gc_ok),a
        ld a,(sl_h) : add a,8 : and 31 : call gc_march : ld (gc_a),a
        ld a,(sl_h) : sub 8 : and 31 : call gc_march : ld b,a
        ld a,(gc_a) : add a,b : ld (gc_w),a             ; width of the road across the line
        ld a,(gc_a) : sub b : sra a : ld (gc_off),a   ; (free steps one way - the other way) / 2
        ret
gc_march:                                           ; A = heading -> A = free steps from the start point
        call sl_vec
        ld hl,(sl_x0) : ld (sl_x),hl : ld hl,(sl_y0) : ld (sl_y),hl
        ld b,100
.l:     call sl_adv
        ld a,(sl_y+1) : ld d,a : ld a,(sl_x+1) : ld e,a
        ld hl,BANK_GROUND : call bitat : jr nc,.e
        ld hl,BANK_WALL : call bitat : jr c,.e
        djnz .l
.e:     ld a,100 : sub b : ret
gc_ok:  db 0
gc_a:   db 0
gc_off: db 0
gc_w:   db 0

grid_calc:                                          ; C = slot -> g_x,g_y,gp_lat : two cars a row, rows behind the line
        call grid_centre
        ld a,(gc_w) : cp 70 : ld a,24 : jr nc,.dl
        ld a,18                                       ; a narrow road: the two cars of a row sit closer together
.dl:    ld (gp_lat),a
.try:   ld hl,(sl_x0) : ld (sl_x),hl : ld hl,(sl_y0) : ld (sl_y),hl
        ld a,(sl_h) : add a,16 : and 31 : call sl_vec
        ld a,(gp_lat) : or a : jr nz,.two
        ld d,c : ld e,22 : mul d,e : ld a,e : add a,14 : jr .r0     ; single file: one car every 22 back
.two:   ld a,14 : bit 1,c : jr z,.t1
        ld a,44
.t1:    bit 0,c : jr z,.r0
        add a,10                                      ; odd slots sit a little further back: a staggered grid
.r0:    ld b,a
.bk:    call sl_adv : djnz .bk
        ld a,(gc_off) : or a : jr z,.nsh                ; slide to the middle of the road
        ld b,a : ld a,(sl_h) : bit 7,b : jr nz,.sn
        add a,8 : jr .sv
.sn:    sub 8 : ld d,a : ld a,b : neg : ld b,a : ld a,d
.sv:    and 31 : call sl_vec
.sh:    call sl_adv : djnz .sh
.nsh:   ld a,(gp_lat) : or a : jr z,.nl
        srl a : ld b,a                                ; half the lateral spacing each side
        ld a,(sl_h) : bit 0,c : jr z,.l1
        add a,8 : jr .l2
.l1:    sub 8
.l2:    and 31 : call sl_vec
.lt:    call sl_adv : djnz .lt
.nl:    ld a,(sl_x+1) : ld (g_x),a : ld a,(sl_y+1) : ld (g_y),a
        ld a,(g_y) : ld d,a : ld a,(g_x) : ld e,a : call solid_at : ret nc
        ld a,(gp_lat) : or a : jr z,.fb
        cp 15 : ld a,14 : jr nc,.set                  ; too tight: narrower grid, then single file
        xor a
.set:   ld (gp_lat),a : jp .try
.fb:    ld hl,(meta_ptr) : ld a,(hl) : ld (g_x),a : inc hl : ld a,(hl) : ld (g_y),a
        ret
gp_lat: db 0
gd_x0:  dw 0
gd_y0:  dw 0
g_x:    db 0
g_y:    db 0

grid_pos:                                           ; C = slot -> IX x,y and heading (facing the line)
        call grid_calc
        ld a,(g_x) : ld (ix+1),a : ld a,(g_y) : ld (ix+3),a
        ld a,(sl_h) : ld (ix+4),a
        ret

draw_grid:                                          ; a "[" slot marking behind the front of each starting position (open towards the line)
        ld c,0
.k:     push bc
        ld a,c : ld e,a : ld d,0 : ld hl,ctl : add hl,de : ld a,(hl)
        cp 7 : jp nc,.nx                              ; UNWANTED: no slot
        cp 6 : jr c,.ok
        ld a,(track_idx) : cp 25 : jp nc,.nx          ; computer cars only race on tracks 1 to 14 for now
.ok:    call grid_calc
        ld a,(g_x) : ld (sl_x+1),a : ld a,(g_y) : ld (sl_y+1),a : ld a,$80 : ld (sl_x),a : ld (sl_y),a
        ld a,(sl_h) : add a,16 : and 31 : call sl_vec
        ld a,(sl_h) : call sl_vec
        ld b,10
.fw:    call sl_adv : djnz .fw                        ; front line sits just ahead of the car
        ld a,(sl_h) : sub 8 : and 31 : call sl_vec
        ld b,9
.lf:    call sl_adv : djnz .lf
        ld hl,(sl_x) : ld (gd_x0),hl : ld hl,(sl_y) : ld (gd_y0),hl   ; front-left corner
        ld a,(sl_h) : add a,8 : and 31 : call sl_vec
        ld b,18 : call gd_seg                         ; front line across
        ld a,(sl_h) : add a,16 : and 31 : call sl_vec
        ld b,8 : call gd_seg                          ; right side back (half length)
        ld hl,(gd_x0) : ld (sl_x),hl : ld hl,(gd_y0) : ld (sl_y),hl
        ld a,(sl_h) : add a,16 : and 31 : call sl_vec
        ld b,8 : call gd_seg                          ; left side back (half length)
.nx:    pop bc : inc c : ld a,c : cp CPU_N : jp c,.k
        ret

gd_seg:                                             ; B steps along the current vector, white pixels where it is clear road
.l:     call sl_adv
        ld a,(sl_y+1) : ld d,a : ld a,(sl_x+1) : ld e,a
        ld hl,BANK_GROUND : call bitat : jr nc,.n
        ld hl,BANK_WALL : call bitat : jr c,.n
        ld a,(sl_x+1) : ld (sl_qx),a : ld a,(sl_y+1) : ld (sl_qy),a : ld a,40 : ld (sl_col),a                      ; light grey (fixed palette entry)
        push bc : call sl_px : pop bc
.n:     djnz .l
        ret

nearest_wp:                                         ; waypoint closest to the car at IX -> A
        ld a,255 : ld (nw_best),a : xor a : ld (nw_i),a : ld (nw_idx),a
.l:     ld a,(nw_i) : call wp_dist
        ld hl,nw_best : cp (hl) : jr nc,.n
        ld (hl),a : ld a,(nw_i) : ld (nw_idx),a
.n:     ld a,(nw_i) : inc a : ld (nw_i),a : ld hl,npts : cp (hl) : jr c,.l
        ld a,(nw_idx)
        ret
nw_best: db 0
nw_i:    db 0
nw_idx:  db 0

update_cars:                                        ; human cars through their own context, computer cars through the lane follower
        ld ix,cpu_t : ld b,CPU_N
.c:     push bc
        ld a,CPU_N : sub b : ld (cur_slot),a
        ld a,(ix+23) : or a : jr z,.n
        cp 1 : jr z,.h
        call cpu_step : jr .n
.h:     call human_step
.n:     ld de,CPU_SZ : add ix,de
        pop bc : djnz .c
        ret

human_step:                                         ; load the car's context into the player variables, run the player physics, store it back
        ld l,(ix+26) : ld h,(ix+27) : ld de,pc_block : ld bc,PCS : ldir
        ld a,(ix+1) : ld (car_x+1),a : ld a,(ix+3) : ld (car_y+1),a : ld a,(ix+5) : ld (speed),a   ; the record is the truth (collisions move it)
        ld a,(ix+25) : call read_dev : ld (cur_in),a
        call update_car
        xor a : ld (lc_hit),a
        call update_lap
        ld a,(lc_hit) : add a,(ix+28) : ld (ix+28),a
        call tick_lap
        ld a,(skid) : or a : jr z,.ns
        ld (snd_skid),a
.ns:    ld hl,pc_block : ld e,(ix+26) : ld d,(ix+27) : ld bc,PCS : ldir
        ld hl,(car_x) : ld (ix+0),l : ld (ix+1),h
        ld hl,(car_y) : ld (ix+2),l : ld (ix+3),h
        ld a,(heading) : ld (ix+4),a : ld a,(speed) : ld (ix+5),a
        ld hl,(best_tenths) : ld (ix+14),l : ld (ix+15),h
        ld a,(boost_cnt) : ld (ix+21),a : ld a,(boost_t) : ld (ix+22),a
        ld a,(laps_done) : ld (ix+24),a
        ret

idx_plus:                                           ; A = waypoint, B = offset -> A = (A+B) mod npts
        add a,b : ld e,a : ld a,(npts) : ld d,a : ld a,e
        cp d : ret c
        sub d : ret

wp_dist:                                            ; A = waypoint -> A = |dx| + 2|dy| from the car (saturating)
        call wp_at
        ld a,(ix+1) : sub b : jr nc,.x : neg
.x:     ld d,a
        ld a,(ix+3) : sub c : jr nc,.y : neg
.y:     add a,a : jr c,.sat
        add a,d : ret nc
.sat:   ld a,255 : ret

smul:                                               ; D x E (signed 8 bit) -> HL signed 16 bit
        ld a,d : xor e : and $80 : ld c,a
        ld a,d : or a : jp p,.p1 : neg : ld d,a
.p1:    ld a,e : or a : jp p,.p2 : neg : ld e,a
.p2:    mul d,e
        ld a,c : or a : jr z,.pos
        ld hl,0 : or a : sbc hl,de : ret
.pos:   ex de,hl : ret

cpu_step:
        ld l,(ix+12) : ld h,(ix+13) : inc hl : ld (ix+12),l : ld (ix+13),h
        inc (ix+16)
; --- passed the waypoint? (closer to the next than to this one)
        ld a,(ix+6) : call wp_dist : ld (dtmp),a
        ld a,(ix+6) : ld b,1 : call idx_plus : ld (ntmp),a : call wp_dist
        ld hl,dtmp : cp (hl) : jr nc,.keep
        ld a,(ntmp) : ld (ix+6),a
.keep:
; --- start/finish line: armed once the last quarter of the circuit is reached, lap counted when the line is crossed
        ld a,(ix+32) : or a : jr nz,.p1                ; lap phase 0: after the line, wait until the lane has wrapped round to its start
        ld a,(npts) : srl a : srl a : ld b,a : ld a,(ix+6) : cp b : jr nc,.na
        ld (ix+32),1 : jr .na
.p1:    cp 1 : jr nz,.p2                                ; phase 1: wait for the second half of the lane
        ld a,(npts) : srl a : ld b,a : ld a,(ix+6) : cp b : jr c,.na
        ld (ix+32),2 : jr .na
.p2:    ld a,(npts) : srl a : srl a : ld b,a : ld a,(npts) : sub b : ld b,a    ; phase 2: the last quarter arms the line
        ld a,(ix+6) : cp b : jr c,.na
        ld (ix+20),1
.na:    call cpu_swap : call line_cross : push af : call cpu_swap : pop af : jr nc,.nl2
        inc (ix+28)                                 ; crossings of the line (race order)
        xor a : ld (ix+32),a                        ; next lap: gates start again
        ld a,(ix+20) : or a : jr z,.first
        ld (ix+20),0 : call cpu_lap : jr .nl2
.first: xor a : ld (ix+12),a : ld (ix+13),a
.nl2:
; --- vector to the target, a few waypoints ahead (x, and y doubled for the iso squash), scaled to signed bytes
        call pick_target                            ; B,C = the farthest lane point this car can see in a straight line
        ld a,(ix+1) : ld l,a : ld a,b : sub l : ld l,a : sbc a,a : ld h,a
        ld a,(ix+3) : ld e,a : ld a,c : sub e : ld e,a : sbc a,a : ld d,a
        ex de,hl : add hl,hl : ex de,hl
.fit:   ld a,l : rla : sbc a,a : cp h : jr nz,.shr
        ld a,e : rla : sbc a,a : cp d : jr z,.fits
.shr:   sra h : rr l : sra d : rr e : jr .fit
.fits:  ld a,l : ld (tx8),a : ld a,e : ld (ty8),a
        call ai_scan                                ; other cars: slow down behind them, swing out round them
        ld a,(ai_bias) : or a : jr z,.nob
        ld a,(tx8) : sra a : ld (tx8),a : ld a,(ty8) : sra a : ld (ty8),a
        ld a,(uy8) : sra a : ld b,a : ld a,(ux8) : sra a : ld c,a
        ld a,(ai_bias) : dec a : jr nz,.br
        ld a,(tx8) : add a,b : ld (tx8),a : ld a,(ty8) : sub c : ld (ty8),a : jr .nob      ; swing left
.br:    ld a,(tx8) : sub b : ld (tx8),a : ld a,(ty8) : add a,c : ld (ty8),a                 ; swing right
.nob:
        ld a,(ix+22) : or a : jr z,.nbt              ; boost running: count down
        dec a : ld (ix+22),a : jr nz,.nbt
        ld a,1 : ld (hud_dirty),a
.nbt:   ld a,(ix+21) : or a : jr z,.nobst            ; use a stored boost on a clear straight
        ld a,(ix+22) : or a : jr nz,.nobst
        ld a,(ix+5) : cp 150 : jr c,.nobst
        ld a,(ai_cap) : cp 255 : jr nz,.nobst        ; nobody ahead
        ld a,(ix+17) : or a : jr nz,.nobst
        call cpu_straight : jr nc,.nobst
        dec (ix+21) : ld (ix+22),BOOST_FRAMES
        ld a,1 : ld (hud_dirty),a
.nobst:
        ld a,(ix+31) : or a : jr z,.norev
        jp .rev                                     ; wedged against a fence: back out first
.norev:
; --- steering tick: quicker when slow
        ld a,(ix+5) : ld b,7 : cp 40 : jr c,.r
        ld b,3 : cp 90 : jr c,.r
        ld b,1 : cp 170 : jr c,.r
        ld b,3
.r:     ld a,(ix+16) : and b : jp nz,.speed
        ld a,(ix+4) : ld e,a : ld d,0
        ld hl,hcos : add hl,de : ld a,(hl) : ld (ux8),a
        ld hl,hsin : add hl,de : ld a,(hl) : ld (uy8),a
        ld a,(ux8) : ld d,a : ld a,(ty8) : ld e,a : call smul : push hl
        ld a,(uy8) : ld d,a : ld a,(tx8) : ld e,a : call smul
        ex de,hl : pop hl : or a : sbc hl,de        ; HL = z = ux*ty - uy*tx  (>0: target is clockwise = right)
        xor a : bit 7,h : jr z,.zp
        inc a
        ex de,hl : ld hl,0 : or a : sbc hl,de       ; HL = |z|
.zp:    ld (zsign),a : ld (zabs),hl
        ld a,(tx8) : or a : jp p,.m1 : neg
.m1:    ld b,a
        ld a,(ty8) : or a : jp p,.m2 : neg
.m2:    cp b : jr c,.m3
        ld b,a
.m3:    ld l,b : ld h,0 : add hl,hl : add hl,hl : add hl,hl : ex de,hl     ; DE = 8*max(|t|)
        ld hl,(zabs) : or a : sbc hl,de : jr c,.straight                  ; |z| < 8m: within ~3 degrees
        ld h,d : ld l,e : add hl,hl : add hl,hl : add hl,de               ; HL = 40m
        ld de,(zabs) : or a : sbc hl,de
        ld a,0 : jr nc,.sf : ld a,1
.sf:    ld (ix+17),a                                                       ; sharp turn needed (>~18 degrees)
        ld a,(ix+4) : ld b,a
        ld a,(zsign) : or a : ld a,b : jr nz,.left
        inc a : jr .tr
.left:  dec a
.tr:    and NHEAD-1 : ld (ix+4),a
        jr .speed
.straight:
        xor a : ld (ix+17),a
; --- speed
.speed: ld a,(ix+17) : or a : jr z,.nocan
        ld (ix+22),0                                 ; a sharp turn cuts a boost short
.nocan: ld a,(ix+11) : ld c,a
        ld a,(ix+22) : or a : jr z,.nbs2
        ld c,255                                     ; boosting: the same top speed as the player's boost
.nbs2:
        ld a,(ai_cap) : cp c : jr nc,.nc1
        ld c,a
.nc1:
        ld a,(ix+17) : or a : jr z,.nl
        ld a,c : cp 130 : jr c,.nl : ld c,130
.nl:    ld a,(ix+5) : cp c : jr z,.mv : jr c,.acc
        sub 3 : cp c : jr nc,.st
        ld a,c : jr .st
.acc:   add a,3 : jr c,.cl
        cp c : jr c,.st
.cl:    ld a,c
.st:    ld (ix+5),a
; --- move
.mv:    ld a,(ix+5) : ld b,a : and $F0 : ld d,a            ; speed level, dithered towards the next level by the low nibble
        ld a,b : and 15 : ld c,a : ld a,(ix+16) : and 15 : cp c : jr nc,.nd
        ld a,d : cp $F0 : jr z,.nd : add a,16 : ld d,a
.nd:    ld a,(speed) : push af
        ld a,d : ld (speed),a
        ld a,(boost_t) : push af : ld a,(ix+22) : ld (boost_t),a      ; each car uses its own boost, not the player's
        ld a,(ix+4) : call step_for
        pop af : ld (boost_t),a
        pop af : ld (speed),a
        ld l,(ix+0) : ld h,(ix+1) : add hl,de : ld (cm_x),hl
        ld l,(ix+2) : ld h,(ix+3) : add hl,bc : ld (cm_y),hl
        ld a,(cm_y+1) : ld d,a : ld a,(cm_x+1) : ld e,a
        call solid_at : jr c,.hit                    ; fences stop computer cars as well: no driving through them
        ld hl,(cm_x) : ld (ix+0),l : ld (ix+1),h
        ld hl,(cm_y) : ld (ix+2),l : ld (ix+3),h
        ld a,(ix+30) : or a : jr z,.nh0 : dec (ix+30)
.nh0:   ld a,(ix+16) : and 63 : ret nz                  ; free for a while: forget the earlier wedges
        ld (ix+33),a
        ret
.hit:   call snd_impact
        inc (ix+30) : ld a,(ix+30) : cp 24 : jr c,.hn      ; 24 net hit frames: the car is wedged, so reverse out
        xor a : ld (ix+30),a
        ld a,(ix+33) : inc a : and 3 : ld (ix+33),a          ; wedged again and again?
        cp 3 : jr nz,.rv0
        ld a,(ix+6) : sub 4 : jr nc,.t1                       ; third time running: something else - back on the lane centre, a few waypoints behind
        ld hl,npts : add a,(hl)
.t1:    call wp_at : xor a : ld (ix+0),a : ld (ix+2),a : ld (ix+1),b : ld (ix+3),c : ld (ix+5),a : ld (ix+33),a
        ret
.rv0:   ld (ix+31),34
.hn:    ld a,(ix+3) : ld d,a : ld a,(cm_x+1) : ld e,a                      ; scrape along the fence: try the x part of the move alone,
        call solid_at : jr c,.sy
        ld hl,(cm_x) : ld (ix+0),l : ld (ix+1),h : jr .sc
.sy:    ld a,(cm_y+1) : ld d,a : ld a,(ix+1) : ld e,a                      ; then the y part alone
        call solid_at : jr c,.sc
        ld hl,(cm_y) : ld (ix+2),l : ld (ix+3),h
.sc:    ld a,(ix+5) : srl a : srl a : srl a : sub (ix+5) : neg : ld (ix+5),a      ; scrub off an eighth of the speed
        ld (ix+22),0
        ret
.rev:   dec (ix+31)                                 ; reversing out: drive backwards while swinging the nose round, then resume the lane
        xor a : ld (ix+17),a : ld (ix+22),a
        ld a,(ix+4) : add a,NHEAD/2 : and NHEAD-1 : ld (ix+4),a
        ld a,110 : ld (ix+5),a
        call .mv
        ld a,(ix+4) : add a,NHEAD/2 : ld b,a
        ld a,(ix+16) : and 3 : jr nz,.rv2                 ; swing one step every 4th frame, direction by slot and lap
        ld a,(cur_slot) : xor (ix+24) : and 1 : jr z,.rl
        inc b : jr .rv2
.rl:    dec b
.rv2:   ld a,b : and NHEAD-1 : ld (ix+4),a
        xor a : ld (ix+5),a
        ret
cm_x:   dw 0
cm_y:   dw 0

; --- racing line: each car aims at the farthest waypoint it can reach in a straight, fence-free line (its own look-ahead limit),
;     so the cars cut corners and take different lines instead of all trailing the lane centreline
pick_target:
        ld a,(cur_slot) : ld e,a : ld d,0
        ld a,(ix+16) : add a,e : add a,e : and 7 : jr nz,.use     ; each car re-looks for its line every 8th frame (staggered)
        ld hl,la_tab : add hl,de : ld a,(hl)
        ld c,a : ld a,(track_idx) : cp 2 : ld a,c : jr c,.k
        ld a,3                                      ; tracks 3 and 4 (narrow spiral, hairpin round a wall end): follow the lane closely
.k:     ld (la_cur),a
.l:     ld a,(la_cur) : ld b,a : ld a,(ix+6) : call idx_plus : call wp_at
        ld a,(la_cur) : cp 4 : jr c,.fix                ; shortest look-ahead: take it
        call los_blocked : jr nc,.fix
        ld hl,la_cur : dec (hl) : dec (hl) : jr .l
.fix:   ld a,(cur_slot) : ld e,a : ld d,0 : ld hl,la_sel : add hl,de : ld a,(la_cur) : ld (hl),a
        ret
.use:   ld hl,la_sel : add hl,de : ld a,(hl) : or a : jr nz,.g
        ld a,3
.g:     ld b,a : ld a,(ix+6) : call idx_plus : jp wp_at
los_blocked:                                        ; carry = a fence lies between the car and (B,C): 7 points along the way (halving)
        push bc
        ld a,(ix+1) : ld (lo_p),a : ld a,(ix+3) : ld (lo_p+1),a
        ld a,b : ld (lo_p+16),a : ld a,c : ld (lo_p+17),a
        ld hl,lo_tab : ld b,7
.l:     push bc
        ld a,(hl) : ld (lo_m),a : inc hl : ld a,(hl) : ld (lo_a),a : inc hl : ld a,(hl) : ld (lo_b),a : inc hl : push hl
        ld a,(lo_a) : call lo_get : ld (lo_t),bc
        ld a,(lo_b) : call lo_get
        ld a,(lo_t+1) : add a,b : rra : ld e,a
        ld a,(lo_t) : add a,c : rra : ld d,a
        ld a,(lo_m) : ld c,a : ld b,0 : ld hl,lo_p : add hl,bc : ld (hl),e : inc hl : ld (hl),d
        call solid_at : jr c,.bad
        pop hl : pop bc : djnz .l
        or a : pop bc : ret
.bad:   pop hl : pop bc : pop bc : scf : ret
lo_get: ld c,a : ld b,0 : ld hl,lo_p : add hl,bc : ld b,(hl) : inc hl : ld c,(hl) : ret
lo_tab: db 8,0,16, 4,0,8, 12,8,16, 2,0,4, 6,4,8, 10,8,12, 14,12,16
lo_p:   ds 18
lo_m:   db 0
lo_a:   db 0
lo_b:   db 0
lo_t:   dw 0
la_tab: db 5,5,3,5
la_cur: db 0
la_sel: db 3,3,3,3

cpu_straight:                                       ; carry = the lane keeps one heading for the next ~14 waypoints
        ld a,(ix+6) : ld e,a : ld d,0 : ld hl,BANK_PATHH : add hl,de : ld b,(hl)       ; B = heading here
        ld a,(ix+6) : ld c,3
.l:     push bc : ld b,4 : call idx_plus : pop bc : ld e,a : ld d,0
        push af : ld hl,BANK_PATHH : add hl,de : ld a,(hl) : sub b : and NHEAD-1
        cp 3 : jr c,.ok
        cp NHEAD-2 : jr nc,.ok
        pop af : or a : ret                          ; turning: no boost
.ok:    pop af : dec c : jr nz,.l
        scf : ret

cpu_lap:                                            ; line crossed with the lap armed: time the lap
        ld l,(ix+12) : ld h,(ix+13)
        ld de,300 : or a : sbc hl,de : jr c,.reset  ; ignore the short first stretch
        inc (ix+24)
        ld a,(ix+24) : call bell_chk
        ld a,(ix+21) : cp 3 : jr nc,.nb             ; every timed lap banks a boost, as for the player
        inc a : ld (ix+21),a
.nb:    ld a,1 : ld (hud_dirty),a
        add hl,de
        add hl,hl : ex de,hl                        ; frames -> hundredths of a second (x2)
.dn:    ld h,d : ld l,e : call lap_flash                 ; show this lap time on the HUD for a while
        ld l,(ix+14) : ld h,(ix+15) : or a : sbc hl,de : jr c,.reset   ; not better than the best
        jr z,.reset
        ld (ix+14),e : ld (ix+15),d
        ld a,1 : ld (hud_dirty),a
.reset: xor a : ld (ix+12),a : ld (ix+13),a
        ret

; --- other cars: the nearest one ahead limits this car's speed and makes it swing out
ai_scan:
        ld a,255 : ld (ai_cap),a : xor a : ld (ai_bias),a
        ld a,(ix+4) : ld e,a : ld d,0
        ld hl,hcos : add hl,de : ld a,(hl) : ld (ux8),a
        ld hl,hsin : add hl,de : ld a,(hl) : ld (uy8),a
        ld a,CPU_N : ld (ai_n),a : ld iy,cpu_t
.l:     push iy : pop de : push ix : pop hl : or a : sbc hl,de : jr z,.skip
        ld a,(iy+23) : or a : jr z,.skip
        ld b,(iy+1) : ld c,(iy+3) : ld a,(iy+5) : call ai_one
.skip:  ld de,CPU_SZ : add iy,de
        ld a,(ai_n) : dec a : ld (ai_n),a : jr nz,.l
        ret

ai_one:                                             ; B,C = other car x,y  A = its speed
        ld (ai_os),a
        ld a,b : sub (ix+1) : jr c,.xn
        bit 7,a : ret nz
        jr .xo
.xn:    bit 7,a : ret z
.xo:    ld (ai_dx),a
        or a : jp p,.xa : neg
.xa:    cp 40 : ret nc
        ld a,c : sub (ix+3) : jr c,.yn
        bit 7,a : ret nz
        jr .yo
.yn:    bit 7,a : ret z
.yo:    or a : jp p,.ya : neg
.ya:    cp 20 : ret nc
        ld a,c : sub (ix+3) : add a,a : ld (ai_dy),a
        ld a,(ux8) : ld e,a : ld a,(ai_dx) : ld d,a : call smul : push hl          ; dx*cos
        ld a,(uy8) : ld e,a : ld a,(ai_dy) : ld d,a : call smul : pop de : add hl,de   ; u = along my heading
        bit 7,h : ret nz
        ld de,3810 : or a : sbc hl,de : ret nc                                     ; only cars within ~30 ahead
        add hl,de : ld (ai_u),hl
        ld a,(uy8) : ld e,a : ld a,(ai_dx) : ld d,a : call smul : push hl          ; dx*sin
        ld a,(ux8) : ld e,a : ld a,(ai_dy) : ld d,a : call smul : pop de : or a : sbc hl,de   ; v = across (>0: on my right)
        ld a,h : ld (ai_vs),a
        bit 7,h : jr z,.va
        ex de,hl : ld hl,0 : or a : sbc hl,de
.va:    ld de,1524 : or a : sbc hl,de : ret nc                                     ; must be within ~12 of my line
        ld hl,(ai_u) : ld de,1524 : or a : sbc hl,de
        jr nc,.nb                                   ; still some way back: just pick a side, keep full speed
        ld a,(ai_os) : add a,4 : jr nc,.cp : ld a,255
.cp:    cp 50 : jr nc,.cm
        ld a,50
.cm:    ld hl,ai_cap : cp (hl) : jr nc,.nb
        ld (hl),a
.nb:    ld a,(ai_bias) : or a : ret nz
        ld a,(ai_vs) : rla : ld a,1 : jr nc,.st     ; other on my right -> swing left, on my left -> swing right
        ld a,255
.st:    ld (ai_bias),a
        ret
ai_cap:  db 255
ai_bias: db 0
ai_n:    db 0
ai_os:   db 0
ai_dx:   db 0
ai_dy:   db 0
ai_vs:   db 0
ai_u:    dw 0

; --- car against car: base footprints (9 x 5) must not overlap; speeds even out and the cars are shoved apart
cars_collide:
        ld hl,cc_buf
        ld ix,cpu_t : ld b,CPU_N
.f:     ld a,(ix+1) : ld (hl),a : inc hl : ld a,(ix+3) : ld (hl),a : inc hl : ld a,(ix+5) : ld (hl),a : inc hl
        ld a,(ix+23) : or a : jr z,.ia
        ld a,1
.ia:    ld (hl),a : inc hl
        ld de,CPU_SZ : add ix,de : djnz .f
        ld hl,cc_pairs : ld b,6
.p:     push bc
        ld e,(hl) : inc hl : ld d,(hl) : inc hl : push de : pop ix
        ld e,(hl) : inc hl : ld d,(hl) : inc hl : push de : pop iy
        push hl : call cc_pair : pop hl
        pop bc : djnz .p
        ld hl,cc_buf
        ld ix,cpu_t : ld b,CPU_N
.w:     ld a,(hl) : ld (ix+1),a : inc hl : ld a,(hl) : ld (ix+3),a : inc hl : ld a,(hl) : ld (ix+5),a : inc hl : inc hl
        ld de,CPU_SZ : add ix,de : djnz .w
        ret

cc_pair:                                            ; IX, IY -> {x,y,speed,active} records
        ld a,(ix+3) : and (iy+3) : ret z
        ld a,(ix+0) : sub (iy+0) : ld d,0 : jr nc,.x1
        neg : ld d,1
.x1:    cp 9 : ret nc : ld b,a                      ; B = |dx|, D = 1 when A is left of B
        ld a,(ix+1) : sub (iy+1) : ld e,0 : jr nc,.y1
        neg : ld e,1
.y1:    cp 5 : ret nc : ld c,a                      ; C = |dy|, E = 1 when A is above B
        call snd_impact                             ; cars touch: thud
        ld a,9 : sub b : ld h,a                     ; penetration in x
        ld a,5 : sub c : add a,a : ld l,a           ; penetration in y (doubled for the iso squash)
        push hl : push de
        ld a,(ix+2) : add a,(iy+2) : rra : ld c,a   ; average speed
        sub 8 : jr nc,.l1
        xor a
.l1:    ld (cc_lo),a
        ld a,c : add a,4 : jr nc,.h1
        ld a,255
.h1:    ld (cc_hi),a
        ld a,(ix+2) : cp (iy+2) : jr c,.bs
        ld a,(cc_lo) : ld (ix+2),a : ld a,(cc_hi) : ld (iy+2),a : jr .sp
.bs:    ld a,(cc_hi) : ld (ix+2),a : ld a,(cc_lo) : ld (iy+2),a
.sp:    pop de : pop hl
        ld a,l : cp h : jr c,.ay                    ; y penetration smaller: separate vertically
        ld c,1 : ld a,d : or a : jr z,.xb           ; A left of B moves left
        ld c,255
.xb:    ld b,0 : call cc_try
        push iy : pop ix : ld a,c : neg : ld c,a : ld b,0 : jp cc_try
.ay:    ld b,1 : ld a,e : or a : jr z,.yb           ; A above B moves up
        ld b,255
.yb:    ld c,0 : call cc_try
        push iy : pop ix : ld a,b : neg : ld b,a : ld c,0 : jp cc_try

cc_try:                                             ; IX = record, C = dx, B = dy (-1..1): shove the car if the spot is free
        ld a,(ix+0) : add a,c : ld e,a : ld a,(ix+1) : add a,b : ld d,a
        push bc : call solid_at : pop bc : ret c
        ld a,(ix+0) : add a,c : ld (ix+0),a
        ld a,(ix+1) : add a,b : ld (ix+1),a
        ret
cc_lo:   db 0
cc_hi:   db 0
cc_buf:  ds 16
cc_pairs: dw cc_buf,cc_buf+4, cc_buf,cc_buf+8, cc_buf,cc_buf+12, cc_buf+4,cc_buf+8, cc_buf+4,cc_buf+12, cc_buf+8,cc_buf+12

restore_all:
        ld ix,cpu_t : ld b,CPU_N
.r:     push bc
        ld a,(ix+23) : or a : jr z,.s
        call cpu_swap : call restore_car : call cpu_swap
.s:     ld de,CPU_SZ : add ix,de
        pop bc : djnz .r
        ret

draw_all:                                           ; nearest the top of the screen first, so lower cars overlap higher ones
        ld ix,cpu_t : ld hl,ord_y : ld b,CPU_N
.o:     ld a,(ix+23) : or a : ld a,255 : jr z,.s
        ld a,(ix+3)
.s:     ld (hl),a : inc hl : ld de,CPU_SZ : add ix,de : djnz .o
        ld b,CPU_N
.round: push bc
        ld hl,ord_y : ld c,255 : ld d,0 : ld e,0 : ld b,CPU_N
.f:     ld a,(hl) : cp 255 : jr z,.sk
        cp c : jr nc,.sk
        ld c,a : ld d,e
.sk:    inc hl : inc e : djnz .f
        ld a,c : cp 255 : jr z,.nx
        ld a,d : ld e,a : ld d,0 : ld hl,ord_y : add hl,de : ld (hl),255
        ld a,e : ld d,a : ld e,CPU_SZ : mul d,e : ld ix,cpu_t : add ix,de
        call cpu_swap : call draw_car : call cpu_swap
.nx:    pop bc : djnz .round
        ret

npts:    db 0
dtmp:    db 0
ntmp:    db 0
tx8:     db 0
ty8:     db 0
ux8:     db 0
uy8:     db 0
zsign:   db 0
zabs:    dw 0
ord_y:   db 0,0,0,0
slot_col: db 0,2,1,3                               ; slot -> car colour: BLUE, RED, GREEN, YELLOW
; computer speed caps per difficulty (EASY, MEDIUM, HARD, EXPERT = as fast as the player) and slot
cap_adj: db 0,-5,3,-8
cpu_caps: db 198,212,191,229, 214,228,206,242, 234,246,224,255, 255,255,255,255
cpu_t:   ds CPU_SZ*CPU_N
