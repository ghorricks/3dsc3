; ===================================================================== second high-score page (mapped at $C000 together with the main one at $E000)
; name entry, the START / PAUSE / QUIT panels and the end-of-race choice live here; the online and file code stays in page HS_PG

name_entry:                                         ; slot in rs_slot, its row (label already shown) in ne_row
        call pn_addr : ld de,ne_idx : ld bc,5 : ldir          ; start from the name this player used last time
        ld c,1 : ld a,(ne_idx) : or a : jr z,.f1 : ld c,0           ; a brand new name ("A" and spaces): each next letter starts from the one just typed
.f1:    ld hl,ne_idx+1 : ld b,4
.f2:    ld a,(hl) : inc hl : cp 36 : jr z,.f3 : ld c,0
.f3:    djnz .f2
        ld a,c : ld (ne_fresh),a
        xor a : ld (ne_pos),a
        call menu_in : ld (ne_prev),a
.draw:  call ne_draw
.w:     call wait_frame : call menu_in : ld b,a
        ld a,(ne_prev) : cpl : and b : ld c,a : ld a,b : ld (ne_prev),a
        ld a,b : and $21 : jr z,.r0                  ; up/down held: repeat every quarter second
        ld a,c : and $21 : jr nz,.r0
        ld hl,ne_rep : inc (hl) : ld a,(hl) : cp 12 : jr c,.rd
        ld a,b : and $21 : or c : ld c,a
.r0:    xor a : ld (ne_rep),a
.rd:
        ld d,1 : bit ACC,c : jr nz,.chg
        ld d,255 : bit DWN,c : jr nz,.chg
        bit LFT,c : jr z,.nl
        ld a,(ne_pos) : or a : jr z,.w
        dec a : ld (ne_pos),a : jr .draw
.nl:    bit BST,c : jr z,.w
        ld a,(ne_pos) : cp 4 : jr z,.done
        ld c,a : ld b,0 : ld hl,ne_idx : add hl,bc : ld a,(ne_fresh) : or a : jr z,.nf2
        inc hl : ld a,(hl) : cp 36 : jr nz,.nf2 : dec hl : ld a,(hl) : inc hl : ld (hl),a
.nf2:   ld a,(ne_pos) : inc a : ld (ne_pos),a : jr .draw
.chg:   ld a,(ne_pos) : ld c,a : ld b,0 : ld hl,ne_idx : add hl,bc : ld a,(hl) : add a,d
        cp 255 : jr nz,.a
        ld a,36
.a:     cp 37 : jr c,.b
        xor a
.b:     ld (hl),a : jp .draw
.done:  call pn_addr : ex de,hl : ld hl,ne_idx : ld bc,5 : ldir      ; remember the name
        ld a,255 : ld (ne_pos),a : jp ne_draw           ; marker away, the name stays in white

; ---- START GAME: every human player types a name for the best laps (remembered from the last game)
pg_names:
        call clear_screen
        ld a,3 : ld (txt_fg),a : ld hl,s_nm1 : ld c,2 : call print_cen
        ld hl,s_nm2 : ld c,4 : call print_cen
        ld a,PROMPT_C : ld (txt_fg),a : ld hl,s_nm3 : ld c,23 : call print_cen
        xor a : ld (pnm_i),a : ld (pnm_k),a                  ; every human car gets a line: coloured label, name in white
.s:     ld a,(pnm_i) : ld e,a : ld d,0 : ld hl,ctl : add hl,de : ld a,(hl) : cp 6 : jr nc,.sn
        call nm_set
        ld a,(pnm_i) : add a,a : ld e,a : ld d,0 : ld hl,col_names : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld a,(pnm_i) : ld e,a : ld d,0 : push hl : ld hl,hud_pos : add hl,de : add hl,de : ld a,(hl) : ld (txt_fg),a : pop hl
        push hl : ld b,11                                    ; right-align: every 'COLOUR NAME' ends where BLUE NAME ends
.ln:    ld a,(hl) : or a : jr z,.lz
        inc hl : djnz .ln
.lz:    ld a,b : ld (txt_col),a : pop hl
        ld a,(ne_row) : ld (txt_row),a
        call print_str : ld hl,s_enter : call print_str
        call pn_addr : ld de,ne_idx : ld bc,5 : ldir
        call ne_name
        ld hl,pnm_k : inc (hl)
.sn:    ld hl,pnm_i : inc (hl) : ld a,(hl) : cp 4 : jr c,.s
        xor a : ld (pnm_i),a : ld (pnm_k),a                  ; then each of them types in turn
.l:     ld a,(pnm_i) : ld e,a : ld d,0 : ld hl,ctl : add hl,de : ld a,(hl) : cp 6 : jr nc,.n      ; computer / unwanted cars have no name
        call nm_set
        call name_entry
        ld hl,pnm_k : inc (hl)
.n:     ld hl,pnm_i : inc (hl) : ld a,(hl) : cp 4 : jr c,.l
        ret
nm_set: ld a,(pnm_i) : ld (rs_slot),a                        ; rs_slot = car, ne_row = its line
        ld a,(pnm_k) : ld c,a : add a,a : add a,c : add a,9 : ld (ne_row),a
        ret
pnm_i:  db 0
pnm_k:  db 0
s_nm1:  db "ENTER YOUR NAME",0
s_nm2:  db "FOR BEST LAP TIMES",0
s_nm3:  db "UP/DOWN=CHANGE   FIRE=NEXT",0

ne_name:
        ld a,3 : ld (txt_fg),a : ld a,18 : ld (txt_col),a : ld a,(ne_row) : ld (txt_row),a
        ld hl,ne_idx : ld b,5
.l:     ld a,(hl) : push hl : push bc : ld e,a : ld d,0 : ld hl,charset : add hl,de : ld a,(hl) : call print_char : pop bc : pop hl : inc hl : djnz .l
        ret
ne_draw:
        call ne_name
        ld a,18 : ld (txt_col),a : ld a,(ne_row) : inc a : ld (txt_row),a
        ld a,(ne_pos) : ld c,a : ld b,0
.c:     ld a,b : cp c : ld a,' ' : jr nz,.p
        ld a,'^'
.p:     push bc : call print_char : pop bc : inc b : ld a,b : cp 5 : jr c,.c
        ret
ne_row: db 0
ne_idx: ds 5
ne_pos: db 0
ne_fresh: db 0
ne_prev: db 0
ne_rep: db 0
s_enter: db " NAME",0

; ---- black panel over the track: PRESS FIRE TO START (practice / race) and PAUSED
pn_box:
        ld a,12 : ld (fr_x),a : ld a,80 : ld (fr_y),a : ld a,232 : ld (fr_w),a : ld a,40 : ld (fr_h),a : ld a,3 : ld (fr_c),a : call fill_rect
        ld a,14 : ld (fr_x),a : ld a,82 : ld (fr_y),a : ld a,228 : ld (fr_w),a : ld a,36 : ld (fr_h),a : xor a : ld (fr_c),a : jp fill_rect
pn_gone:                                            ; the track behind the panel comes back from the clean copy
        ld a,80 : ld (sc_y),a
.row:   ld a,(sc_y) : ld b,a : rlca : rlca : and 3 : add a,a : ld c,a : add a,18 : nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld a,c : add a,CLEAN_PG : nextreg REG_MMU2,a : inc a : nextreg REG_MMU3,a
        ld a,b : and 63 : ld d,a : or $40 : ld h,a : ld e,12 : ld l,12
        ld bc,232 : ldir
        ld hl,sc_y : inc (hl) : ld a,(hl) : cp 120 : jr c,.row
        ret
pg_ready:
        call pn_box
        ld a,PROMPT_C : ld (txt_fg),a
        ld a,(phase) : or a : ld hl,s_rdp : jr z,.m
        ld hl,s_rdr
.m:     ld c,12 : call print_cen
.w0:    call wait_frame : call menu_in : bit BST,a : jr nz,.w0        ; let go of the fire button from the last screen
.w1:    call wait_frame : call menu_in : bit BST,a : jr z,.w1
.w2:    call wait_frame : call menu_in : bit BST,a : jr nz,.w2
        jp pn_gone
pg_pause:
        call silence_all
        call pn_box
        ld a,PROMPT_C : ld (txt_fg),a
        ld hl,s_pz1 : ld c,11 : call print_cen
        ld hl,s_pz2 : ld c,13 : call print_cen
.w0:    call wait_frame : call brk_down : jr z,.w0                    ; BREAK is still down from the press that paused
.w1:    call wait_frame : call brk_down : jr nz,.w1
.w2:    call wait_frame : call brk_down : jr z,.w2
        jp pn_gone
brk_down:                                           ; Z when Caps Shift and Space are both down
        ld bc,$FEFE : in a,(c) : bit 0,a : jr nz,.n
        ld b,$7F : in a,(c) : bit 0,a : jr nz,.n
        xor a : ret
.n:     or 1 : ret
pg_quit:                                            ; ENTER / START in a race: A = 0 continue, 1 end the race (practice), 2 quit to the menu
        call silence_all
        call pn_box
        ld hl,s_er : ld de,s_ers : ld a,(phase) : or a : jr nz,.t
        ld hl,s_ep : ld de,s_eps
.t:     ld (qt_tab+4),hl : ld (qt_tab+6),de
        xor a : ld (qt_sel),a
.dr:    xor a : ld (qt_i),a
.d:     ld a,PROMPT_C : ld (txt_fg),a
        ld a,(qt_i) : add a,11 : ld c,a : ld b,6 : ld hl,s_blk3 : call print_at
        ld a,(qt_sel) : ld e,a : ld a,(qt_i) : ld d,a : add a,a : ld c,a : ld a,d : cp e : ld a,c : jr nz,.n1
        inc a
.n1:    add a,a : ld e,a : ld d,0 : ld hl,qt_tab : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld a,(qt_i) : add a,11 : ld c,a : call print_cen
        ld hl,qt_i : inc (hl) : ld a,(hl) : cp 3 : jr c,.d
.w0:    call wait_frame : call menu_in : or a : jr nz,.w0               ; everything let go first (ENTER is still down)
        call menu_in : ld (qt_pv),a
.w:     call wait_frame : call menu_in : ld b,a
        ld a,(qt_pv) : cpl : and b : ld c,a : ld a,b : ld (qt_pv),a
        bit BST,c : jr nz,.go
        bit ACC,c : jr z,.nu
        ld a,(qt_sel) : or a : jr nz,.u1
        ld a,3
.u1:    dec a : ld (qt_sel),a : jp .dr
.nu:    bit DWN,c : jr z,.w
        ld a,(qt_sel) : inc a : cp 3 : jr c,.d1
        xor a
.d1:    ld (qt_sel),a : jp .dr
.go:    call pn_gone
        ld a,(qt_sel) : ret
qt_sel: db 0
qt_i:   db 0
qt_pv:  db 0
qt_tab: dw s_co,s_cos, s_ep,s_eps, s_qm,s_qms
s_co:   db "CONTINUE",0
s_cos:  db "> CONTINUE <",0
s_ep:   db "END PRACTICE",0
s_eps:  db "> END PRACTICE <",0
s_er:   db "END RACE",0
s_ers:  db "> END RACE <",0
s_qm:   db "QUIT TO MENU",0
s_qms:  db "> QUIT TO MENU <",0
s_blk3: db "                    ",0
s_rdp:  db "PRESS FIRE TO START PRACTICE",0
s_rdr:  db "PRESS FIRE TO START RACE",0
s_pz1:  db "PAUSED",0
s_pz2:  db "PRESS BREAK TO CONTINUE",0

; ---- end of a race: NEXT TRACK / MAIN MENU (A = 1 for the next track, 0 for the main menu)
pg_choice:
        xor a : ld (ch_sel),a
.setup: ld a,(sc_on) : or a : jr z,.nsc
        call copy_l2_to_clean                           ; the table as it is now: the scroll below redraws it from this copy
        xor a : ld (sc_off),a : ld a,2 : ld (sc_dir),a : ld a,50 : ld (sc_pause),a
.nsc:
        ld a,54 : ld (fr_x),a : ld a,153 : ld (fr_y),a : ld a,148 : ld (fr_w),a : ld a,34 : ld (fr_h),a : ld a,3 : ld (fr_c),a : call fill_rect
        ld a,56 : ld (fr_x),a : ld a,155 : ld (fr_y),a : ld a,144 : ld (fr_w),a : ld a,30 : ld (fr_h),a : xor a : ld (fr_c),a : call fill_rect

.dr:    xor a : ld (ch_i),a
.d:     ld a,PROMPT_C : ld (txt_fg),a
        ld a,(ch_i) : add a,a : add a,20 : ld c,a : ld b,9 : ld hl,s_blk2 : call print_at
        ld a,(ch_sel) : ld e,a : ld a,(ch_i) : ld d,a : add a,a : ld c,a : ld a,d : cp e : ld a,c : jr nz,.n1      ; table index = item * 2 (+1 when selected)
        inc a
.n1:    add a,a : ld e,a : ld d,0 : ld hl,ch_tab : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld a,(ch_i) : add a,a : add a,20 : ld c,a : call print_cen
        ld hl,ch_i : inc (hl) : ld a,(hl) : cp 2 : jr c,.d
.w0:    call wait_frame : call menu_in : bit BST,a : jr nz,.w0         ; let go of Space/fire first
        call menu_in : ld (ch_pv),a
.w:     call wait_frame : call pl_tick : call sc_step : call menu_in : ld b,a
        ld a,(ch_pv) : cpl : and b : ld c,a : ld a,b : ld (ch_pv),a
        bit BST,c : jr nz,.go
        bit LFT,c : jr z,.nl3                           ; over the table: LEFT / RIGHT swap LOCAL and ONLINE
        xor a : jr .vm
.nl3:   bit RGT,c : jr z,.nr3
        ld a,1
.vm:    ld b,a : ld a,(sc_on) : or a : jr z,.w
        ld a,b : ld (hv_mode),a : call pg_vredraw : jp .setup
.nr3:   ld a,c : and $21 : jr z,.w
        ld a,(ch_sel) : xor 1 : ld (ch_sel),a : jp .dr
.go:    xor a : ld (sc_on),a : ld (pl_on),a : ld a,(ch_sel) : xor 1 : ret
s_blk2 equ s_blk3+6                                  ; 14 spaces: the tail of the 20
sc_on:    db 0
sc_off:   db 0
sc_dir:   db 2
sc_pause: db 0
sc_y:     db 0
sc_step:                                        ; the high-score list moves up (so entry 10 shows above the panel), waits a second, moves back, waits ...
        ld a,(sc_on) : or a : ret z
        ld a,(sc_pause) : or a : jr z,.mv
        dec a : ld (sc_pause),a : ret
.mv:    ld a,(sc_off) : ld hl,sc_dir : add a,(hl) : ld (sc_off),a
        jr z,.top
        cp 48 : jr nz,.dr
        ld a,254 : ld (sc_dir),a : ld a,50 : ld (sc_pause),a : jr .dr
.top:   ld a,2 : ld (sc_dir),a : ld a,50 : ld (sc_pause),a
.dr:    ld a,24 : ld (sc_y),a
.row:   ld a,(sc_y) : ld b,a
        rlca : rlca : and 3 : add a,a : add a,18 : nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld a,b : and 63 : ld d,a : ld e,0
        ld a,(sc_off) : add a,b : cp 192 : jr nc,.blk
        ld c,a : rlca : rlca : and 3 : add a,a : add a,CLEAN_PG : nextreg REG_MMU2,a : inc a : nextreg REG_MMU3,a
        ld a,c : and 63 : or $40 : ld h,a : ld l,0
        ld bc,256 : ldir : jr .nx
.blk:   ld h,d : ld l,e : ld (hl),0 : inc de : ld bc,255 : ldir
.nx:    ld hl,sc_y : inc (hl) : ld a,(hl) : cp 153 : jr c,.row
        ret
ch_sel: db 0
ch_i:   db 0
ch_pv:  db 0
ch_tab: dw s_nt,s_nts,s_mm,s_mms
s_nt:   db "NEXT TRACK",0
s_nts:  db "> NEXT TRACK <",0
s_mm:   db "MAIN MENU",0
s_mms:  db "> MAIN MENU <",0

; ---- BEST LAPS screens: left/right pick the track, up/down switch LOCAL / ONLINE, fire leaves
pg_best:                                            ; HL = best lap (tenths) saved for the current track
        call hs_ptr : ld de,5 : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl : ret
pg_vredraw:                                         ; draw the table again (hv_mode says which), without waiting
        ld a,2 : ld (hv_cont),a : ld a,(track_idx) : ld (hv_sv),a
        call pg_view.redraw
        xor a : ld (hv_cont),a
        ret
pg_view:
        ld a,(track_idx) : ld (hv_sv),a
        xor a : ld (hv_mode),a
.redraw:
        call clear_screen
        ld hl,s_hl
        ld a,3 : ld (txt_fg),a : ld b,6 : ld c,0 : call print_at
        ld a,(track_idx) : inc a : call print_dec2
        ld a,3 : ld (txt_fg),a : ld hl,s_sw1 : ld b,0 : ld c,1 : call print_at          ; PRESS LEFT/RIGHT <LOCAL> ONLINE: names in green, the one shown has white < > around it
        ld a,20 : ld (txt_fg),a : ld hl,s_sw2 : ld e,23 : ld a,(hv_mode) : or a : jr z,.nm   ; only the table being shown: <LOCAL> or <ONLINE>
        ld hl,s_sw4 : ld e,24
.nm:    push de : ld b,18 : ld c,1 : call print_at
        ld a,3 : ld (txt_fg),a : ld hl,s_lt : ld b,17 : ld c,1 : call print_at
        pop de : ld b,e : ld hl,s_gt : ld c,1 : call print_at
        ld a,(hv_mode) : or a : jr z,.loc
        call net_fetch                              ; HL = this track's online records, A = how many (0 when the server can't be reached)
        jr .go
.loc:   call hs_ptr : ld a,20
.go:    ld (hv_p),hl : ld (hv_n),a
        xor a : ld (hv_i),a
.r:     ld a,(hv_n) : ld b,a : ld a,(hv_i) : cp b : jp nc,.dn
        add a,3 : ld (txt_row),a
        ld a,(hv_mode) : or a : jr nz,.nn0                ; is this one of the records just set? (local table of that track, after a race / practice)
        ld a,(hv_cont) : or a : jr z,.nn0
        ld a,(track_idx) : ld hl,nw_trk : cp (hl) : jr nz,.nn0
        ld a,(hv_i) : ld e,a : ld d,0 : ld hl,nw_tab : add hl,de : ld a,(hl) : jr .nn1
.nn0:   xor a
.nn1:   ld (hv_nw),a
        ld a,9 : ld (txt_col),a : ld a,4 : call pcol : ld (txt_fg),a
        ld a,(hv_i) : inc a : call print_dec2
        ld a,' ' : call print_char
        ld a,3 : call pcol : ld (txt_fg),a           ; name in white
        ld hl,(hv_p) : ld b,5
.n:     ld a,(hl) : inc hl : push hl : push bc : call print_char : pop bc : pop hl : djnz .n
        ld (hv_p),hl : ld a,' ' : call print_char
        ld a,20 : call pcol : ld (txt_fg),a          ; time in green
        ld hl,(hv_p) : ld e,(hl) : inc hl : ld d,(hl) : inc hl : inc hl : ld (hv_p),hl
        ex de,hl : call print_tenths
        ld hl,hv_i : inc (hl) : jp .r
.dn:    ld a,(hv_n) : or a : jr nz,.pr
        ld hl,s_off : ld c,10 : call print_cen         ; online and nothing came back
        call net_show
.pr:    ld a,(hv_cont) : cp 2 : jr nz,.pr1
        ld a,(hv_sv) : ld (track_idx),a : ret
.pr1:   ld a,PROMPT_C : ld (txt_fg),a : ld hl,s_ret : ld a,(hv_cont) : or a : jr z,.pc
        ld hl,s_cont
.pc:    ld c,23 : call print_cen
        call menu_in : ld (hv_pr),a
.w:     call wait_frame : call pl_tick : call menu_in : ld b,a
        ld a,(hv_pr) : cpl : and b : ld c,a : ld a,b : ld (hv_pr),a
        ld d,1 : bit ACC,c : jr nz,.ch                  ; UP / DOWN: next / previous track
        ld d,255 : bit DWN,c : jr nz,.ch
        bit LFT,c : jr z,.nl2
        xor a : jr .sw                                   ; LEFT: local
.nl2:   bit RGT,c : jr z,.nr2
        ld a,1 : jr .sw                                  ; RIGHT: online
.nr2:
        bit BST,c : jr z,.w
        ld a,(hv_sv) : ld (track_idx),a
        xor a : ld (pl_on),a
        ret
.sw:    ld (hv_mode),a : jp .redraw
.ch:    ld a,(trk_max) : ld b,a : ld a,(track_idx) : call wrapadd : ld (track_idx),a : jp .redraw
hv_sv: db 0
hv_p:  dw 0
hv_i:  db 0
hv_n:  db 0
hv_pr: db 0
hv_mode: db 0
s_hl:  db "BEST LAPS - TRACK ",0
s_sw1: db "PRESS LEFT/RIGHT",0
s_sw2: db "LOCAL",0
s_sw4: db "ONLINE",0
s_lt:  db "<",0
s_gt:  db ">",0
s_off: db "SERVER NOT AVAILABLE",0
s_ne:  db "NET ERROR  STAGE ",0
net_show:                                           ; the reason a call failed: stage and error code (hex)
        ld a,3 : ld (txt_fg),a : ld a,3 : ld (txt_col),a : ld a,13 : ld (txt_row),a
        ld hl,s_ne : call print_str
        ld a,(net_stage) : add a,'0' : call print_char
        ld a,' ' : call print_char
        ld a,(net_err) : call .b
        ld a,' ' : call print_char : ld a,(net_len+1) : call .b : ld a,(net_len)
.b:     push af : rrca : rrca : rrca : rrca : call .h : pop af
.h:     and 15 : add a,'0' : cp ':' : jr c,.p
        add a,7
.p:     jp print_char
s_ret: db "PRESS FIRE TO RETURN TO MENU",0
s_cont: db "PRESS FIRE TO CONTINUE",0
hv_cont: db 0

; ---- race screen, bottom right: L BEST (local) / O BEST (online), swapped every 5 seconds
pg_pre:                                             ; before the track is drawn: fetch the online tables once (its message must not end up on the track)
        ld a,(oc_ok) : or a : ret nz
        ld a,(oc_try) : or a : ret nz
        inc a : ld (oc_try),a
        jp net_fetch
pg_binit:
        xor a : ld (bs_mode),a : ld (bs_t),a : dec a : ld (bs_off),a
        call hs_ptr : ld de,bs_lname : ld bc,5 : ldir        ; the local best: who and how fast
        call pg_best : ld (bs_loc),hl
        ld de,9999 : or a : sbc hl,de : jr c,.l1
        ld hl,bs_lname : call blank5
.l1:    ld a,(oc_ok) : or a : jr z,.none
.go:    call net_fetch                                  ; A = entries of this track, HL = first (best) entry
        or a : jr z,.none
        push hl : ld de,bs_oname : ld bc,5 : ldir : pop hl
        ld de,5 : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ld (bs_onl),de : jr .x
.none:  ld hl,$FFFF : ld (bs_onl),hl : ld hl,bs_oname : call blank5
.x:     jr pg_bdraw0
blank5: ld b,5 : ld a,' '
.b:     ld (hl),a : inc hl : djnz .b
        ret
pg_bflip:                                            ; every 6 frames: 10 seconds per table - the time, scrolled left to the name, back again, then the other table
        ld a,(bs_t) : inc a : cp 84 : jr c,.k
        xor a : ld (bs_t),a : ld a,(bs_mode) : xor 1 : ld (bs_mode),a
        ld a,255 : ld (bs_off),a : xor a : jr .c
.k:     ld (bs_t),a
.c:     cp 15 : jr c,.z
        cp 20 : jr c,.u
        cp 35 : jr c,.f
        cp 40 : jr c,.d
.z:     xor a : jr .s
.u:     sub 14 : jr .s
.f:     ld a,6 : jr .s
.d:     ld b,a : ld a,39 : sub b
.s:     ld hl,bs_off : cp (hl) : ret z
        ld (hl),a
pg_bdraw0:
        call pg_bdraw : jp bsync
pg_bdraw:                                            ; line "L BEST 14.7 NAME " (17 characters), the 12 from bs_off on are shown in the corner
        ld a,3 : ld (txt_fg),a
        ld a,(bs_mode) : or a : ld hl,s_lbest : ld de,(bs_loc) : ld bc,bs_lname : jr z,.m
        ld hl,s_obest : ld de,(bs_onl) : ld bc,bs_oname
.m:     ld (bs_v),de : ld (bs_np),bc
        ld de,bs_line : ld bc,7 : ldir                       ; DE = bs_line+7
        ld hl,(bs_v) : push de : ld de,9999 : or a : sbc hl,de : pop de : jr c,.v
        ld hl,s_dash : ld bc,5 : ldir : jr .nm
.v:     ld hl,(bs_v) : call cs_fmt
.nm:    ld a,' ' : ld (de),a : inc de
        ld hl,(bs_np) : ld bc,5 : ldir
        xor a : ld (de),a
        ld a,(bs_off) : cp 7 : jr c,.o
        xor a
.o:     ld e,a : ld d,0 : ld hl,bs_line : add hl,de : ld de,bs_win : ld bc,12 : ldir
        xor a : ld (de),a
        ld hl,bs_win : ld b,20 : ld c,23 : jp print_at
bsync:                                                  ; the corner (rows y 184..191, x 160..255) also goes into the clean copy, so cars restore the new text
        ld a,2 : ld (win_pg),a : call map_windows
        ld hl,$3800+160 : ld de,$7800+160 : ld b,8
.r:     push bc : ld bc,96 : ldir : ld bc,160 : add hl,bc : ex de,hl : add hl,bc : ex de,hl : pop bc : djnz .r
        ret
bs_mode: db 0
bs_t:    db 0
bs_off:  db 255
bs_v:    dw 0
bs_np:   dw 0
bs_lname: ds 5
bs_oname: ds 5
s_dash:  db "--.--"
bs_line: ds 19
bs_win:  ds 14
bs_loc:  dw $FFFF
bs_onl:  dw $FFFF
s_lbest: db "L BEST ",0
s_obest: db "O BEST ",0


