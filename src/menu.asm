; ===================================================================== main menu
; CAR 1..4 : choose a controller for each car (or COMPUTER / UNWANTED), DIFFICULTY, TRACK, LAPS, START, INSTRUCTIONS
; Q/A or joystick up/down move, left/right (O/P) change, fire (Space / Enter / pad button) selects.
MENU_ROWS   equ 10

menu_run:
        xor a : out ($FE),a : nextreg $4A,0
        call clear_screen
        ld a,3 : ld (txt_fg),a
        call hs_logo
        ld a,3 : ld (txt_fg),a
        ld b,7 : ld c,3 : ld hl,s_by : call print_at
        ld a,3 : ld (txt_fg),a                      ; bottom centre: VERSION : build
        ld b,7 : ld c,23 : ld hl,s_vlab : call print_at
        ld b,17 : ld c,23 : ld hl,s_ver : call print_at
        ld a,(upd_flag) : add a,MENU_ROWS : ld (mrows),a        ; a newer build on the server adds the UPDATE item
        call menu_draw
        ld a,(mu_msg) : or a : jr z,.nm                 ; back from a U key update check
        xor a : ld (mu_msg),a
        ld a,(upd_flag) : or a : jr nz,.nm
        ld a,PROMPT_C : ld (txt_fg),a : ld hl,s_nonew : ld c,19 : call print_cen
.nm:    call menu_in : ld (prev_in),a
.loop:  call wait_frame
        call menu_ukey
        call menu_in : ld b,a
        ld a,(prev_in) : cpl : and b : ld c,a       ; C = newly pressed
        ld a,b : ld (prev_in),a
        ld a,(menu_sel) : ld e,a : ld (md_old),a
        bit ACC,c : jr z,.nu
        ld a,(mrows) : ld b,a : dec a : add a,e : cp b : jr c,.su
        sub b
.su:    ld (menu_sel),a : call menu_drawsel : jr .loop
.nu:    bit DWN,c : jr z,.nd
        ld a,(mrows) : ld b,a : ld a,e : inc a : cp b : jr c,.sd
        xor a
.sd:    ld (menu_sel),a : call menu_drawsel : jr .loop
.nd:    ld d,1 : bit RGT,c : jr nz,.chg
        ld d,255 : bit LFT,c : jr nz,.chg
        bit BST,c : jr z,.loop
        ld a,e : cp 7 : jr nz,.b8
        call menu_instr : jp menu_run
.b8:    cp 10 : jr nz,.b9
        call hs_update : jp menu_run                ; download the newer build
.b9:    cp 8 : jr nz,.start
        call hs_view : jp menu_run
.chg:   call menu_change : ld a,(menu_sel) : call menu_row : jp .loop
.start: ld hl,ctl : ld b,4                          ; humans enter names; all-computer races start straight away
.h:     ld a,(hl) : cp 6 : jr c,.ok
        inc hl : djnz .h
        ld hl,ctl : ld b,4                          ; no human: four computers is fine (no names to enter), but somebody has to race
.cc:    ld a,(hl) : cp 6 : ret z
        inc hl : djnz .cc
        jp .loop
.ok:    jp hs_names                               ; every human player enters a name for the best laps first

menu_ukey:                                          ; U: check the server for a newer build (does not return: the menu is drawn again)
        ld bc,$DFFE : in a,(c) : bit 3,a : ret nz
        pop af
        call hs_vcheck
.ur:    call wait_frame : ld bc,$DFFE : in a,(c) : bit 3,a : jr z,.ur     ; let go of U first
        ld a,1 : ld (mu_msg),a
        jp menu_run

menu_change:                                        ; E = row, D = +1 / -1
        ld a,e : cp 4 : jr nc,.o
        ld (mc_i),a : ld c,a : ld b,0 : ld hl,ctl : add hl,bc : ld a,(hl)
.st:    ld b,8 : call wrapadd : cp 6 : jr nc,.ok          ; COMPUTER / UNWANTED may repeat, a controller only once
        ld c,a : ld hl,ctl : ld b,4 : ld e,0
.ck:    ld a,(mc_i) : cp e : jr z,.sk
        ld a,(hl) : cp c : jr z,.taken
        cp 4 : jr nz,.o9                            ; CURSOR shares keys 5-8 and 0 with INT2 L and INT2 R: those pairs would fight over the keyboard
        ld a,c : cp 2 : jr z,.taken : cp 3 : jr z,.taken : jr .sk
.o9:    ld a,c : cp 4 : jr nz,.sk
        ld a,(hl) : cp 2 : jr z,.taken : cp 3 : jr z,.taken
.sk:    inc hl : inc e : djnz .ck
        ld a,c : jr .ok
.taken: ld a,c : jr .st
.ok:    ld c,a : ld a,(mc_i) : ld e,a : ld d,0 : ld hl,ctl : add hl,de : ld (hl),c : ret
.o:     jr nz,.o1
        ld a,(difficulty) : ld b,4 : call wrapadd : ld (difficulty),a : ret
.o1:    cp 5 : jr nz,.o2
        ld a,(trk_max) : ld b,a : ld a,(track_idx) : call wrapadd : ld (track_idx),a : ret
.o2:    cp 6 : ret nz
        ld a,(laps_i) : ld b,8 : call wrapadd : ld (laps_i),a
        add a,3 : ld (laps_total),a                  ; 3..10 laps, no practice-only
        ret
mc_i:   db 0

wrapadd:                                            ; A + D modulo B
        add a,d : cp 255 : jr nz,.n
        ld a,b : dec a : ret
.n:     cp b : ret c
        xor a : ret

menu_drawsel:                                       ; the highlight moved: only the row it left and the row it arrived on are redrawn (no flicker elsewhere)
        ld a,(md_old) : call menu_row
        ld a,(menu_sel)
menu_row:                                           ; A = menu row to redraw
        ld (md_lo),a : inc a : ld (md_end),a
        jr menu_drw
menu_draw:
        xor a : ld (md_lo),a : ld a,(mrows) : ld (md_end),a
menu_drw:                                           ; rows md_lo .. md_end-1: selected row "< value >" (or "> ITEM <"); each row is cleared and redrawn
        ld a,(md_lo) : ld c,a
.r:     push bc
        ld e,c : ld d,0 : ld hl,row_tab : add hl,de : ld a,(hl) : ld (md_row),a   ; screen row
        ld a,(menu_sel) : cp c : ld a,0 : jr nz,.s0
        inc a
.s0:    ld (md_sel),a
        ld a,(md_row) : ld c,a : ld b,0 : ld hl,s_blk : call print_at
        pop bc : push bc
        ld a,c : cp 4 : jr nc,.o
        ld e,a : ld d,0 : ld hl,hud_pos : add hl,de : add hl,de : ld a,(hl) : ld (txt_fg),a    ; the car's own colour
        ld a,c : add a,a : ld e,a : ld d,0 : ld hl,car_names : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld a,(md_row) : ld c,a : ld b,7 : call print_at
        pop bc : push bc
        ld a,c : ld e,a : ld d,0 : ld hl,ctl : add hl,de : ld a,(hl) : add a,a : ld e,a : ld d,0
        ld hl,ctl_names : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld (md_str),hl
        ld a,(md_row) : ld c,a : ld b,15 : call print_at
        ld a,15 : ld (md_col),a : jp .vm
.o:     cp 7 : jp nc,.cen
        ld a,4 : ld (txt_fg),a
        ld a,c : sub 4 : add a,a : ld e,a : ld d,0 : ld hl,row_names : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld a,(md_row) : ld c,a : ld b,2 : call print_at
        pop bc : push bc
        ld a,c : cp 4 : jr nz,.r5
        ld a,(difficulty) : add a,a : ld e,a : ld d,0 : ld hl,diff_names : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        jr .pv
.r5:    cp 5 : jr nz,.r6
        ld a,3 : ld (txt_fg),a : ld a,15 : ld (txt_col),a : ld (md_col),a : ld a,(md_row) : ld (txt_row),a
        ld a,(track_idx) : inc a : call print_dec2
        ld d,2 : jr .vm2
.r6:    ld a,3 : ld (txt_fg),a : ld a,15 : ld (txt_col),a : ld (md_col),a : ld a,(md_row) : ld (txt_row),a
        ld a,(laps_i) : add a,3 : call print_dec2
        ld d,2 : jr .vm2
.pv:    ld (md_str),hl : ld a,15 : ld (md_col),a
        ld a,(md_row) : ld c,a : ld b,15 : call print_at
.vm:    ld hl,(md_str) : call tlen : ld d,a
.vm2:   ld a,(md_col) : ld b,a : ld a,(md_row) : ld c,a : call mv_mark
        jr .nx
.cen:   ld a,c : cp 10 : jr nz,.c8                   ; UPDATE TO ########: cyan, "> ... <" when selected
        ld a,PROMPT_C : ld (txt_fg),a : ld hl,upd_msg : ld a,(md_sel) : or a : jr z,.cu
        ld hl,upd_sel
.cu:    ld a,(md_row) : ld c,a : call print_cen : jr .nx
.c8:    ld a,4 : ld (txt_fg),a                       ; INSTRUCTIONS / BEST LAPS, centred; START GAME is a prompt: cyan
        ld a,c : cp 9 : jr nz,.c4
        ld a,PROMPT_C : ld (txt_fg),a
.c4:
        ld a,c : sub 7 : ld b,a : ld a,(md_sel) : ld e,a : add a,a : add a,e : add a,b : add a,a : ld e,a : ld d,0
        ld hl,cen_tab : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld a,(md_row) : ld c,a : call print_cen
.nx:    pop bc : inc c : ld a,c : ld hl,md_end : cp (hl) : jp c,.r
        ret
row_tab: db 6,7,8,9,12,13,14,17,18,21,4
md_row:  db 0
mu_msg:  db 0
s_nonew: db "NO NEWER BUILD FOUND",0
md_lo:   db 0
md_end:  db 0
md_old:  db 0
md_sel:  db 0
md_str:  dw 0
md_col:  db 0
mv_l:    db 0
mv_c:    db 0
mv_r:    db 0
s_blk:   db "                                ",0
s_isel:  db "> INSTRUCTIONS <",0
s_bsel:  db "> BEST LAPS <",0
cen_tab: dw s_ins0,rn5,s_start,s_isel,s_bsel,s_ssel
s_start: db "START GAME",0
s_ssel:  db "> START GAME <",0

tlen:                                               ; HL = string -> A = its length without trailing spaces
        ld b,0
.f:     ld a,(hl) : or a : jr z,.e
        inc hl : inc b : jr .f
.e:     ld a,b : or a : ret z
        dec hl : ld a,(hl) : cp ' ' : jr nz,.d
        dec b : jr .e
.d:     ld a,b : ret

mv_mark:                                            ; selected row: "<" two columns left of the value (col B, row C), ">" after D characters
        ld a,(md_sel) : or a : ret z
        ld a,b : ld (mv_c),a : ld a,c : ld (mv_r),a : ld a,d : ld (mv_l),a
        ld a,3 : ld (txt_fg),a
        ld a,(mv_c) : sub 2 : ld (txt_col),a : ld a,(mv_r) : ld (txt_row),a : ld a,'<' : call print_char
        ld a,(mv_c) : ld b,a : ld a,(mv_l) : add a,b : inc a : ld (txt_col),a : ld a,'>' : jp print_char

menu_instr:    nextreg REG_MMU6,LOGO_PG : call pg_instr : jp map_track     ; the instructions screen lives in page 81, at $C000

s_by:     db "BY GAVIN HORRICKS",0
s_vlab:   db "VERSION : ",0
s_ins0:   db "INSTRUCTIONS",0
car_names:  dw cn1,cn2,cn3,cn4
cn1: db "CAR 1",0
cn2: db "CAR 2",0
cn3: db "CAR 3",0
cn4: db "CAR 4",0
ctl_names:  dw c0,c1,c2,c3,c4,c5,c6,c7
c0: db "KEMPSTON 1 ",0
c1: db "KEMPSTON 2 ",0
c2: db "INT2 L     ",0
c3: db "INT2 R     ",0
c4: db "CURSOR     ",0
c5: db "KEYS QAOPSP",0
c6: db "COMPUTER   ",0
c7: db "UNWANTED   ",0
row_names: dw rn1,rn2,rn3
rn1: db "       CPU",0              ; right-aligned with TRACK and LAPS
rn2: db "     TRACK",0              ; padded so the three labels are right-aligned
rn3: db "      LAPS",0
rn5: db "BEST LAPS",0
diff_names: dw d0,d1,d2,d3
d0: db "EASY  ",0
d1: db "MEDIUM",0
d2: db "HARD  ",0
d3: db "EXPERT",0

; ===================================================================== results after practice / race
show_results:
        call silence_all
        xor a : out ($FE),a : nextreg $4A,0
        call clear_screen
        ld a,3 : ld (txt_fg),a
        ld a,(phase) : or a : ld hl,s_pover : ld b,8 : jr z,.t
        ld hl,s_rover : ld b,10
.t:     ld c,2 : call print_at
        ld a,(phase) : or a : jr z,.kp
        call race_keys : jr .kk
.kp:    ld ix,cpu_t : ld iy,ro_key : ld b,CPU_N          ; practice: best laps
.pl:    ld a,(ix+14) : ld (iy+0),a : ld a,(ix+15) : ld (iy+1),a
        cp $27 : jr c,.pk : ld (iy+0),$0F : ld (iy+1),$27              ; no lap time = 99.99
.pk:        ld de,CPU_SZ : add ix,de : inc iy : inc iy : djnz .pl
.kk:    call rank_all
        ld a,(phase) : or a : call nz,merge_finished
        ld a,(ro_n) : ld b,a : ld c,0
.l:     ld a,b : or a : jp z,.done
        push bc
        ld a,c : ld e,a : ld d,0 : ld hl,pos_ord : add hl,de : ld e,(hl)
        ld a,e : ld (rs_slot),a
        ld d,0 : ld hl,hud_pos : add hl,de : add hl,de : ld a,(hl) : ld (txt_fg),a
        ld a,c : add a,a : add a,6 : ld (txt_row),a
        ld a,(rs_slot) : add a,a : ld e,a : ld d,0 : ld hl,col_names : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl      ; the colour name ...
        ld a,(rs_slot) : ld e,a : ld d,0 : push hl : ld hl,ctl : add hl,de : ld a,(hl) : pop hl : cp 6 : jr nc,.cn
        ld a,(rs_slot) : call hs_pname              ; ... or the player's own name for a human car
.cn:    ld (rs_str),hl : call tlen
        ld a,11 : ld (rs_nc),a                      ; columns: #n, then the name straight after "#n - " (YELLOW is the widest), the time right aligned
        ld a,6 : ld (txt_col),a
        ld a,'#' : call print_char
        pop bc : push bc : ld a,c : add a,'1' : call print_char
        ld a,' ' : call print_char : ld a,'-' : call print_char : ld a,' ' : call print_char
        ld a,(rs_nc) : ld (txt_col),a
        ld hl,(rs_str) : call print_str
        ld a,17 : ld (txt_col),a
        ld a,' ' : call print_char : ld a,'-' : call print_char : ld a,' ' : call print_char
        ld a,(rs_slot) : ld d,a : ld e,CPU_SZ : mul d,e : ld hl,cpu_t+14 : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld a,h : cp $27 : jr c,.tt
        ld hl,9999
.tt:    call print_tenths
.nt:    pop bc : inc c : dec b : jp nz,.l
.done:  ld a,PROMPT_C : ld (txt_fg),a : ld hl,s_pfc : ld c,22 : call print_cen    ; results stay up until the player decides to go on
.d0:    call wait_frame : call menu_in : bit BST,a : jr nz,.d0
.d1:    call wait_frame : call menu_in : bit BST,a : jr z,.d1
.d2:    call wait_frame : call menu_in : bit BST,a : jr nz,.d2
        call hs_check_all : jr nc,.np                ; practice laps count too
        ld a,(phase) : or a : jp z,hs_sync           ; practice records entered: table shown, then to the server, straight on
.np:    ld a,(phase) : or a : jr z,.p0
        call hs_choice : jp hs_sync       ; race over: NEXT TRACK or MAIN MENU, then the records go to the server
.p0:    ld a,PROMPT_C : ld (txt_fg),a
        ld a,(phase) : or a : jr nz,.pm
        ld a,(laps_total) : or a : jr z,.pm
        ret                                         ; practice then race: the track screen shows PRESS FIRE TO START RACE itself
.pm:    ld hl,s_pmenu : ld b,6
        ld c,18 : call print_at
.w:     call wait_frame : call menu_in : bit BST,a : jr nz,.w          ; let go of Space first
.w2:    call wait_frame : call menu_in : bit BST,a : jr z,.w2
.w3:    call wait_frame : call menu_in : bit BST,a : jr nz,.w3
        ret
rs_slot: db 0
rs_str:  dw 0
rs_nc:   db 0
res_col: db 7,8,7,6
s_pfc:    db "PRESS FIRE TO CONTINUE",0
s_pover:  db "PRACTICE IS OVER",0
s_rover:  db "RACE IS OVER",0
s_pmenu:  db "PRESS SPACE FOR MENU",0
col_names: dw cb,cr,cg,cy
cb: db "BLUE",0
cr: db "RED",0
cg: db "GREEN",0
cy: db "YELLOW",0

merge_finished:                                     ; race: cars that finished (in the order they did) go before the ones still running
        ld hl,pos_ord : ld de,pos_tmp : ld bc,4 : ldir
        ld a,(fin_n) : or a : ret z
        ld a,(ro_n) : or a : jr z,.nu
        ld c,a : ld b,0 : ld a,(fin_n) : ld e,a : ld d,0 : ld hl,pos_ord : add hl,de : ex de,hl : ld hl,pos_tmp : ldir
.nu:    ld a,(fin_n) : ld (rs_k),a : ld a,1 : ld (rs_w),a
.fp:    ld ix,cpu_t : ld c,0 : ld b,CPU_N
.fs:    ld a,(rs_w) : cp (ix+29) : jr z,.got
        ld de,CPU_SZ : add ix,de : inc c : djnz .fs
        jr .nx
.got:   ld a,(rs_w) : dec a : ld e,a : ld d,0 : ld hl,pos_ord : add hl,de : ld (hl),c
.nx:    ld hl,rs_w : inc (hl) : ld hl,rs_k : dec (hl) : jr nz,.fp
        ld a,(ro_n) : ld hl,fin_n : add a,(hl) : ld (ro_n),a
        ret
pos_tmp: ds 4
rs_k: db 0
rs_w: db 0

print_str:                                          ; HL = string, drawn at txt_col/txt_row
.l:     ld a,(hl) : or a : ret z
        push hl : call print_char : pop hl : inc hl : jr .l

print_cen:                                          ; HL = string, C = row: centred on the screen
        push hl : ld b,0
.l:     ld a,(hl) : or a : jr z,.d
        inc hl : inc b : jr .l
.d:     ld a,32 : sub b : srl a : ld b,a : pop hl
        jp print_at
