; ===================================================================== best laps + online scores
; Lives in RAM page HS_PG, which is mapped at $E000 while any of this runs (the stubs in main.asm map it).
; $E000-$E77F: 24 tracks x 10 entries x 8 bytes: name (5), time in tenths (2), synced flag (1 = on the server).
; Code from $E800.  Local table is saved to 3DSC3.SAV; new records are sent to the online table with the .http dot command.
HS_ENT      equ $E000

pg_init:                                            ; every record starts as 3DSC3 99.9S
        ld de,HS_ENT : ld a,240
.l:     push af : ld hl,hs_def : ld bc,8 : ldir : pop af : dec a : jr nz,.l
        ld hl,pn_def : ld de,pn_tab : ld bc,20 : ldir
        call sv_load                                ; records and player names saved by an earlier session
        ld hl,pn_tab : ld b,4                       ; old saves hold PLAY1..PLAY4 as the unchosen name: back to a plain "A"
.mg:    ld a,(hl) : cp 15 : jr nz,.mn
        push hl : inc hl : ld a,(hl) : cp 11 : jr nz,.mp
        inc hl : ld a,(hl) : or a : jr nz,.mp
        inc hl : ld a,(hl) : cp 24 : jr nz,.mp
        pop hl : xor a : ld (hl),a : inc hl : ld a,36 : ld (hl),a : inc hl : ld (hl),a : inc hl : ld (hl),a : inc hl : ld (hl),a : inc hl : djnz .mg : jr .md
.mp:    pop hl
.mn:    ld de,5 : add hl,de : djnz .mg
.md:
        call net_sync                               ; and any that never reached the server
        jp pg_vcheck                                ; and is there a newer build?
hs_def: db "3DSC3",$E7,$03,1
HS_NAMES    equ HS_ENT+1920                         ; the four players' names (5 character indices each) are saved with the table
pn_tab      equ HS_NAMES
pn_def:     db 0,36,36,36,36, 0,36,36,36,36, 0,36,36,36,36, 0,36,36,36,36     ; just an "A" until a player types a name

hs_ptr:                                             ; -> HL = first entry of the current track
        ld a,(track_idx) : ld d,a : ld e,80 : mul d,e : ld hl,HS_ENT : add hl,de
        ret

hs_rank:                                            ; DE = tenths -> A = place 0..9, or 10 when it does not make the table
        push de : call hs_ptr : push hl : pop ix : pop de
        xor a : ld (hr_i),a
.l:     ld c,(ix+5) : ld b,(ix+6) : ld h,d : ld l,e : or a : sbc hl,bc : jr c,.f
        ld bc,8 : add ix,bc : ld a,(hr_i) : inc a : ld (hr_i),a : cp 10 : jr c,.l
.f:     ld a,(hr_i)
        ret
hr_i:   db 0

hs_insert:                                          ; A = place, DE = tenths, name in hn_buf
        ld (hi_r),a : ld (hi_t),de
        push de : call nw_ins : pop de                 ; remember which entries are new (they pulse in the table)
        ld b,a : ld a,9 : sub b : ld d,a : ld e,8 : mul d,e : ld b,d : ld c,e     ; BC = bytes to move down
        call hs_ptr : ld de,71 : add hl,de : push hl : ld de,8 : add hl,de : ex de,hl : pop hl
        ld a,b : or c : jr z,.nm
        lddr
.nm:    call hs_ptr : ld a,(hi_r) : add a,a : add a,a : add a,a : ld e,a : ld d,0 : add hl,de
        ex de,hl : ld hl,hn_buf : ld bc,5 : ldir
        ld hl,(hi_t) : ld a,l : ld (de),a : inc de : ld a,h : ld (de),a
        inc de : xor a : ld (de),a                  ; not on the server yet
        ret
hi_r:   db 0
hi_t:   dw 0
hn_buf: ds 5

; ---- after a race: every human car whose best lap makes the table enters a name; then save, send and show the table
pg_check:
        xor a : ld (hc_i),a : ld (hc_any),a : ld (pl_on),a : dec a : ld (nw_trk),a
.l:     ld a,(hc_i) : ld hl,ro_n : cp (hl) : jr c,.go
        ld a,(hc_any) : or a : ret z
        call sv_save                                ; local file first; the server gets them once the player has decided how to go on (pg_sync)
        ld a,1 : ld (sy_pend),a
        ld a,(phase) : or a : ld a,1 : jr z,.vw
        inc a : push af : ld a,1 : ld (sc_on),a : pop af     ; race: the table is shown without waiting, NEXT TRACK / MAIN MENU follows (the table scrolls behind it)
.vw:    ld (hv_cont),a
        call pg_view : xor a : ld (hv_cont),a : scf : ret
.go:
        ld e,a : ld d,0 : ld hl,pos_ord : add hl,de : ld a,(hl) : ld (rs_slot),a
        ld e,a : ld hl,ctl : add hl,de : ld a,(hl) : cp 6 : jr nc,.n                 ; computer cars take no records
        ld a,(rs_slot) : ld d,a : ld e,CPU_SZ : mul d,e : ld hl,cpu_t+14 : add hl,de : ld e,(hl) : inc hl : ld d,(hl)
        ld h,d : ld l,e : ld bc,999 : or a : sbc hl,bc : jr nc,.n                    ; no lap time
        ld (hi_t),de
        call hs_rank
        cp 10 : jr nc,.n
        call pn_apply : ld a,1 : ld (hc_any),a
.n:     ld hl,hc_i : inc (hl) : jr .l
sy_pend: db 0
pg_sync:                                            ; send the new records, with the message
        ld a,(sy_pend) : or a : ret z
        xor a : ld (sy_pend),a
        call net_sync
        xor a : ld (oc_ok),a : ld (oc_try),a        ; the tables on the server changed: fetch them again
        ret
hc_i:   db 0
hc_any: db 0

clr_low:                                            ; blank rows 14-21
        xor a : ld (fr_x),a : ld (fr_c),a : ld a,112 : ld (fr_y),a : ld a,255 : ld (fr_w),a : ld a,64 : ld (fr_h),a
        jp fill_rect

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

pg_pname:                                           ; A = car -> HL = the player's name as text (pn_buf in main memory), trailing spaces removed
        ld (rs_slot),a : call pn_addr
        ld de,pn_buf : ld b,5
.c:     ld a,(hl) : inc hl : push hl : push de : ld e,a : ld d,0 : ld hl,charset : add hl,de : ld a,(hl) : pop de : ld (de),a : inc de : pop hl : djnz .c
        xor a : ld (de),a : ld b,4
.t:     dec de : ld a,(de) : cp ' ' : jr nz,.d
        xor a : ld (de),a : djnz .t
.d:     ld hl,pn_buf : ret
pn_addr:                                            ; HL = this player's name (rs_slot) in pn_tab
        ld a,(rs_slot) : ld e,a : add a,a : add a,a : add a,e : ld e,a : ld d,0 : ld hl,pn_tab : add hl,de
        ret
pn_apply:                                           ; a record was set: enter the player's remembered name in the table
        call pn_addr : ld de,hn_buf : ld b,5
.cv:    ld a,(hl) : inc hl : push hl : push de : ld e,a : ld d,0 : ld hl,charset : add hl,de : ld a,(hl) : pop de : ld (de),a : inc de : pop hl : djnz .cv
        ld de,(hi_t) : call hs_rank : cp 10 : ret nc
        ld de,(hi_t) : jp hs_insert

; ---- START GAME: every human player types a name for the best laps (remembered from the last game)
pg_names:
        call clear_screen
        ld a,3 : ld (txt_fg),a : ld hl,s_nm1 : ld c,2 : call print_cen
        ld hl,s_nm2 : ld c,4 : call print_cen
        ld a,PROMPT_C : ld (txt_fg),a : ld hl,s_nm3 : ld c,22 : call print_cen
        xor a : ld (pnm_i),a : ld (pnm_k),a                  ; every human car gets a line: coloured label, name in white
.s:     ld a,(pnm_i) : ld e,a : ld d,0 : ld hl,ctl : add hl,de : ld a,(hl) : cp 6 : jr nc,.sn
        call nm_set
        ld a,(pnm_i) : add a,a : ld e,a : ld d,0 : ld hl,col_names : add hl,de : ld e,(hl) : inc hl : ld d,(hl) : ex de,hl
        ld a,(pnm_i) : ld e,a : ld d,0 : push hl : ld hl,hud_pos : add hl,de : add hl,de : ld a,(hl) : ld (txt_fg),a : pop hl
        ld a,4 : ld (txt_col),a : ld a,(ne_row) : ld (txt_row),a
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
s_nm3:  db "UP/DOWN LETTER  FIRE NEXT",0

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
charset: db "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
ne_row: db 0
ne_idx: ds 5
ne_pos: db 0
ne_fresh: db 0
ne_prev: db 0
ne_rep: db 0
s_enter: db " NAME",0

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
        ld a,3 : ld (txt_fg),a : ld hl,s_sw1 : ld b,2 : ld c,2 : call print_at          ; UP/DOWN: LOCAL OR ONLINE - the one being shown in green
        ld a,(hv_mode) : or a : ld a,20 : jr z,.lg
        ld a,3
.lg:    ld (txt_fg),a : ld hl,s_sw2 : ld b,15 : ld c,2 : call print_at
        ld a,3 : ld (txt_fg),a : ld hl,s_sw3 : ld b,21 : ld c,2 : call print_at
        ld a,(hv_mode) : or a : ld a,3 : jr z,.og
        ld a,20
.og:    ld (txt_fg),a : ld hl,s_sw4 : ld b,23 : ld c,2 : call print_at
        ld a,(hv_mode) : or a : jr z,.loc
        call net_fetch                              ; HL = this track's online records, A = how many (0 when the server can't be reached)
        jr .go
.loc:   call hs_ptr : ld a,10
.go:    ld (hv_p),hl : ld (hv_n),a
        xor a : ld (hv_i),a
.r:     ld a,(hv_n) : ld b,a : ld a,(hv_i) : cp b : jp nc,.dn
        add a,a : add a,4 : ld (txt_row),a
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
        ex de,hl : call print_tenths : ld a,'S' : call print_char
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
.ch:    ld a,(track_idx) : ld b,24 : call wrapadd : ld (track_idx),a : jp .redraw
hv_sv: db 0
hv_p:  dw 0
hv_i:  db 0
hv_n:  db 0
hv_pr: db 0
hv_mode: db 0
s_hl:  db "BEST LAPS - TRACK ",0
s_sw1: db "LEFT/RIGHT = ",0
s_sw2: db "LOCAL",0
s_sw3: db "/",0
s_sw4: db "ONLINE",0
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

; ===================================================================== online (.http dot command, plain HTTP)
NET_BANK    equ 41                                  ; 16K bank (8K pages 82/83) that receives the reply
NET_PG      equ 82
net_host:   db "3dsc3.silent-cloud-35d4.workers.dev",0
s_c1:       db ".http -h ",0
s_c5:       db " -f 3DSC3.TMP",0
s_c2:       db " -u /?track=",0
s_all:      db "all",0
nb_all:     db 0
nb_ver:     db 0
s_cv:       db " -u /?version",0
s_cd:       db " -u /?download=",0
s_cf:       db " -f ",0
s_chk:      db "CHECKING FOR UPDATES...",0

; --- once at start: the server's version.txt ("26111830,releases/....nex,size,crc") says which build is newest
pg_vcheck:
        xor a : ld (upd_flag),a
        ld a,3 : ld (txt_fg),a : ld hl,s_chk : ld c,12 : call print_cen
        ld a,1 : ld (nb_ver),a
        call net_clear : call nb_base : call nb_end
        call net_try                                       ; one attempt only: nobody should wait long for this
        ld b,a : xor a : ld (nb_ver),a : ld (fr_x),a : ld (fr_c),a
        ld a,96 : ld (fr_y),a : ld a,255 : ld (fr_w),a : ld a,8 : ld (fr_h),a
        push bc : call fill_rect : pop bc                  ; wipe the message
        ld a,b : or a : ret nz
        nextreg REG_MMU6,NET_PG
        ld hl,$C000 : ld de,upd_ver : ld b,8
.c:     ld a,(hl) : sub '0' : cp 10 : ret nc
        add a,'0' : ld (de),a : inc hl : inc de : djnz .c
        ld hl,upd_ver : ld de,s_ver : ld b,8               ; compare with this build
.k:     ld a,(de) : cp (hl) : jr c,.new
        ret nz
        inc hl : inc de : djnz .k
        ret
.new:   ld a,1 : ld (upd_flag),a
        ld hl,upd_ver : ld de,upd_sv : ld bc,8 : ldir        ; the selected form of the menu text
        ld hl,$C000 : ld de,upd_line : ld bc,64 : ldir       ; keep the whole line: path and size
        ret
upd_line:   ds 64
            db 0
s_c3:       db "&name=",0
s_c4:       db "&time=",0

net_exec:   ld hl,nb+1                                         ; "http ..." - no leading dot for M_EXECCMD
            call hs_exec                                       ; M_EXECCMD from main memory, with the OS memory layout
            jr c,.e
            xor a : ret
.e:         ld (net_err),a : ld a,1 : ld (net_stage),a : ret   ; A = 1 when the command failed
net_err:    db 0
net_len:    dw 0
net_stage:  db 0                                               ; 1 dot command refused, 2 no reply file, 3 empty reply, 4 server said ERROR

nb_put:     ld a,(hl) : or a : ret z
            ld (de),a : inc hl : inc de : jr nb_put
nb_base:    ld de,nb : ld hl,s_c1 : call nb_put
            ld hl,net_host : call nb_put
            ld a,(nb_ver) : or a : jr z,.nv
            ld hl,s_cv : jp nb_put                              ; ?version: the newest build number and where to get it
.nv:        ld hl,s_c2 : call nb_put
            ld a,(nb_all) : or a : jr z,.num
            ld hl,s_all : jp nb_put                            ; ?track=all: every table in one reply
.num:       ld a,(ns_t) : inc a : ld b,'0'
.t:         cp 10 : jr c,.o
            sub 10 : inc b : jr .t
.o:         ld c,a : ld a,b : cp '0' : jr z,.s
            ld (de),a : inc de
.s:         ld a,c : add a,'0' : ld (de),a : inc de
            ret
nb_dg:      ld a,'0'                                           ; HL / BC -> digit at (DE), remainder in HL
.l:         or a : sbc hl,bc : jr c,.d
            inc a : jr .l
.d:         add hl,bc : ld (de),a : inc de : ret
nb_end:     ld hl,s_c5 : call nb_put                           ; reply goes to a file, read back with esxDOS
            ld a,13 : ld (de),a : inc de : xor a : ld (de),a : ret

net_clear:  nextreg REG_MMU6,NET_PG                            ; reply bank at $C000
            ld hl,$C000 : ld de,$C001 : ld bc,511 : ld (hl),0 : ldir
            ret

net_fetch:  ld a,(oc_ok) : or a : jr nz,.use                        ; the online tables are fetched once, with ?track=all
            ld hl,s_wait : ld c,12 : call print_cen
            ld a,1 : ld (nb_all),a
            call net_clear
            call nb_base : call nb_end
            call net_run : or a : jr nz,.fail
            call net_parse
            ld a,1 : ld (oc_ok),a
.fail:      xor a : ld (nb_all),a
            ld (fr_x),a : ld (fr_c),a : ld a,96 : ld (fr_y),a : ld a,255 : ld (fr_w),a : ld a,8 : ld (fr_h),a
            call fill_rect                                     ; wipe the message
.use:       nextreg REG_MMU6,NET_PG
            ld a,(oc_ok) : or a : jr z,.none
            ld a,(track_idx) : ld e,a : ld d,0
            ld hl,OC_CNT : add hl,de : ld a,(hl) : push af
            ld h,d : ld l,e : add hl,hl : add hl,hl : add hl,de : add hl,hl : add hl,hl : add hl,hl : add hl,hl   ; 80 per track
            ld de,OC_ENT : add hl,de : pop af : ret
.none:      ld hl,OC_ENT : xor a : ret
net_run:    call net_try : ret z                                ; A = 0 when a reply arrived
            call net_try                                       ; the WiFi module sometimes drops a request: once more
            or a : ret
net_try:    call net_unlink                                    ; old reply out of the way
            call net_exec : or a : jr nz,.e
            nextreg REG_MMU6,NET_PG
            call net_rd
            or a
.e:         ret
net_unlink: nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF
            ld a,'*' : ld ix,tmp_name : rst 8 : db $AD : ret
net_rd:     ld b,1 : ld ix,tmp_name : call sv_open2 : jr nc,.o
            ld (net_err),a : ld a,2 : ld (net_stage),a : ld a,1 : ret
.o:
            ld (sv_h),a : ld ix,$C000 : ld bc,4000 : rst 8 : db $9D : ld (net_len),bc : call sv_close
            ld hl,$C000 : ld bc,(net_len) : add hl,bc : ld (hl),0                        ; end of text
            ld a,($C000) : or a : jr z,.f
            xor a : ret
.f:         ld a,3 : ld (net_stage),a : ld a,1 : ret
tmp_name:   db "3DSC3.TMP",0

; --- parse the ?track=all reply: "T,NAME,42.3" lines at $C000 into the cache (page 82: counts at OC_CNT, 10 x 8 bytes per track at OC_ENT)
OC_CNT      equ $D000
OC_ENT      equ $D100
net_parse:  ld hl,OC_CNT : ld de,OC_CNT+1 : ld bc,23 : ld (hl),0 : ldir
            ld hl,$C000
.ln:        ld a,(hl) : or a : ret z
            ld (np_ln),hl : ld d,0
.td:        ld a,(hl) : cp ',' : jr z,.tk
            sub '0' : cp 10 : jr nc,.sk
            ld e,a : ld a,d : add a,a : ld c,a : add a,a : add a,a : add a,c : add a,e : ld d,a
            inc hl : jr .td
.tk:        inc hl : ld a,d : or a : jr z,.sk
            dec a : cp 24 : jr nc,.sk
            ld (np_t),a : ld e,a : ld d,0
            push hl : ld hl,OC_CNT : add hl,de : ld a,(hl) : pop hl
            cp 10 : jr nc,.sk                                  ; the table of a track holds 10 records
            ld (np_c),a
            push hl
            ld a,(np_t) : ld e,a : ld d,0 : ld h,d : ld l,e
            add hl,hl : add hl,hl : add hl,de : add hl,hl : add hl,hl : add hl,hl : add hl,hl
            ld a,(np_c) : add a,a : add a,a : add a,a : ld e,a : ld d,0 : add hl,de
            ld de,OC_ENT : add hl,de : ex de,hl
            pop hl
            call np_rec : jr c,.sk
            ld a,(np_t) : ld e,a : ld d,0 : ld hl,OC_CNT : add hl,de : inc (hl)
.sk:        ld hl,(np_ln) : call skipl : jr .ln
np_rec:                                                         ; HL -> "NAME,SS.T", DE -> 8-byte record; carry = malformed
            ld (np_s),hl : ld b,0
.fc:        ld a,(hl) : cp ',' : jr z,.hc
            or a : jr z,.bad
            cp 10 : jr z,.bad
            cp 13 : jr z,.bad
            inc hl : inc b : ld a,b : cp 6 : jr c,.fc
.bad:       scf : ret
.hc:        ld a,b : or a : jr z,.bad
            push hl
            ld hl,(np_s) : ld c,b : ld b,5
.cp:        ld a,c : or a : ld a,' ' : jr z,.pd
            ld a,(hl) : inc hl : dec c
.pd:        ld (de),a : inc de : djnz .cp
            pop hl : inc hl : ld bc,0
.dg:        ld a,(hl) : cp '.' : jr z,.fr
            sub '0' : cp 10 : jr nc,.bad
            call add_dig : inc hl : jr .dg
.fr:        xor a : call add_dig
            inc hl : ld a,(hl) : sub '0' : cp 10 : jr c,.t
            xor a
.t:         ld l,a : ld h,0 : add hl,bc
            ex de,hl : ld (hl),e : inc hl : ld (hl),d
            or a : ret
np_ln:      dw 0
np_t:       db 0
np_c:       db 0
oc_try:     db 0                                                ; 1 = the online tables were already tried this round
oc_ok:      db 0                                                ; 1 = the online tables in page 82 are current
add_dig:    push hl : ld h,b : ld l,c : add hl,hl : add hl,hl : add hl,bc : add hl,hl
            ld c,a : ld b,0 : add hl,bc : ld b,h : ld c,l : pop hl : ret
skipl:      ld a,(hl) : or a : ret z
            inc hl : cp 10 : jr nz,skipl
            ret
np_s:       dw 0

; --- send every record that is not on the server yet (stops at the first failure: offline)
net_sync:   xor a : ld (sy_fail),a : ld (ns_t),a : ld (sy_msg),a : ld (sy_chg),a
            ld ix,HS_ENT
.tr:        ld b,10
.en:        ld a,(ix+7) : or a : jr nz,.nx
            ld l,(ix+5) : ld h,(ix+6) : ld de,999 : or a : sbc hl,de : jr nc,.nx          ; default 99.9 entries are not scores
            push bc
            ld a,(sy_msg) : or a : jr nz,.go
            inc a : ld (sy_msg),a
            push ix : call clear_screen : ld a,3 : ld (txt_fg),a : ld hl,s_send : ld c,11 : call print_cen : pop ix      ; text drawing clobbers IX
.go:        call net_post
            pop bc
            or a : jr z,.ok
            ld (sy_fail),a : jr .end
.ok:        ld (ix+7),1 : ld a,1 : ld (sy_chg),a
.nx:        ld de,8 : add ix,de : dec b : jp nz,.en
            ld hl,ns_t : inc (hl) : ld a,(hl) : cp 24 : jp c,.tr
.end:       ld a,(sy_fail) : or a : jr z,.sv
            call net_show : ld b,150
.wt:        push bc : call wait_frame : pop bc : djnz .wt
.sv:        ld a,(sy_chg) : or a : ret z
            jp sv_save                                          ; synced flags to disk
sy_msg:     db 0
sy_fail:    db 0
sy_chg:     db 0
ns_t:       db 0

net_post:   call net_clear                                      ; IX = entry of track ns_t -> A = 0 when sent
            call nb_base
            push ix : ld hl,s_c3 : call nb_put
            pop ix
            ld b,5 : push ix
.nm:        ld a,(ix+0) : inc ix : cp ' ' : jr nz,.c
            ld a,'%' : ld (de),a : inc de : ld a,'2' : ld (de),a : inc de : ld a,'0'
.c:         ld (de),a : inc de : djnz .nm
            pop ix
            ld hl,s_c4 : call nb_put
            ld l,(ix+5) : ld h,(ix+6)
            ld bc,100 : call nb_dg : ld bc,10 : call nb_dg
            ld a,'.' : ld (de),a : inc de
            ld a,l : add a,'0' : ld (de),a : inc de
            call nb_end
            push ix : call net_run : pop ix
            or a : ret nz
            ld a,($C000) : cp 'E' : jr z,.f                     ; "ERROR: ..." from the server
            xor a : ret
.f:         ld a,4 : ld (net_stage),a : ld a,1 : ret
s_send:     db "SENDING BEST LAPS TO THE SERVER",0
s_wait:     db "CONTACTING SERVER...",0

; ===================================================================== esxDOS file access to 3DSC3.SAV (table is read/written in place)
sv_open:    ld ix,sv_name
sv_open2:   nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF      ; the esxDOS trap wants ROM at 0000-3FFF
            ld a,'*' : rst 8 : db $9A : ret
sv_load:    ld b,1 : call sv_open : ret c
            ld (sv_h),a : ld ix,HS_ENT : ld bc,1940 : rst 8 : db $9D : jr sv_close
sv_save:    ld b,$0E : call sv_open : ret c                   ; write, create or truncate
            ld (sv_h),a : ld ix,HS_ENT : ld bc,1940 : rst 8 : db $9E
sv_close:   ld a,(sv_h) : rst 8 : db $9B : ret
sv_h:       db 0
sv_name:    db "3DSC3.SAV",0

; ---- instructions screen (moved here to free main code space)
pg_instr:
        call clear_screen
        ld a,3 : ld (txt_fg),a
        ld b,10 : ld c,1 : ld hl,s_ins0 : call print_at
        ld a,4 : ld (txt_fg),a
        ld hl,ins_tab : ld c,3
.l:     ld e,(hl) : inc hl : ld d,(hl) : inc hl
        ld a,d : or e : jr z,.w
        push hl : ex de,hl : push bc
        ld a,4 : push hl : ld de,i11 : or a : sbc hl,de : pop hl : jr nz,.c4
        ld a,PROMPT_C
.c4:    ld (txt_fg),a : call print_cen : pop bc : pop hl
        inc c : jr .l
.w:     call menu_in : or a : jr nz,.w                ; let go of the key that brought us here
.w2:    call wait_frame : call menu_in : or a : jr z,.w2
.w3:    call wait_frame : call menu_in : or a : jr nz,.w3
        ret

ins_tab:  dw i1,i2,i3,i4,i5,i6,i10,i12,i11,0
i1:  db "Q ACCEL  A BRAKE/REVERSE",0
i2:  db "O LEFT P RIGHT SPACE BOOST",0
i3:  db "KEMPSTON: A/B ACCELERATE",0
i4:  db "C BRAKE DOWN REVERSE UP BOOST",0
i5:  db "CROSS THE LINE FOR A BOOST",0
i6:  db "BOOST: 1.5X SPEED FOR 2 SECS",0
i10: db "ENTER OR START LEAVES A RACE",0
i12: db "SYMBOL SHIFT+SPACE ENDS IT",0
i11: db "PRESS FIRE TO RETURN",0


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
        ld de,999 : or a : sbc hl,de : jr c,.l1
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
.f:     ld a,5 : jr .s
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
        ld de,bs_line : ld bc,7 : ldir
        ld ix,bs_line+7 : ld hl,(bs_v) : ld de,999 : or a : sbc hl,de : jr c,.v
        ld (ix+0),'-' : ld (ix+1),'-' : ld (ix+2),'.' : ld (ix+3),'-' : jr .nm
.v:     ld hl,(bs_v) : ld de,100 : ld c,'0'
.h3:    or a : sbc hl,de : jr c,.h4
        inc c : jr .h3
.h4:    add hl,de : ld (ix+0),c : ld a,l : ld c,'0'
.t:     sub 10 : jr c,.t2
        inc c : jr .t
.t2:    add a,10 : add a,'0' : ld (ix+3),a : ld (ix+1),c : ld (ix+2),'.'
.nm:    ld (ix+4),' ' : ld hl,(bs_np) : ld de,bs_line+12 : ld bc,5 : ldir
        xor a : ld (de),a
        ld a,(bs_off) : cp 6 : jr c,.o
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
bs_line: ds 19
bs_win:  ds 14
bs_loc:  dw $FFFF
bs_onl:  dw $FFFF
s_lbest: db "L BEST ",0
s_obest: db "O BEST ",0

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

; ---- main menu title logo: yellow bold letters with a red drop shadow
pg_logo:
        ld a,24 : ld (lg_c),a : ld a,10 : ld (lg_x),a : ld a,6 : ld (lg_y),a : call lg_draw
        ld a,4 : ld (lg_c),a : ld a,8 : ld (lg_x),a : ld a,4 : ld (lg_y),a
lg_draw:
        nextreg REG_MMU6,LOGO_PG : ld hl,$C000 : xor a : ld (lg_r),a
.row:   push hl
        ld a,(lg_x) : ld e,a : ld a,(lg_y) : ld d,a : ld a,(lg_r) : add a,d : call l2_row_addr
        pop hl : ld ixl,30
.byte:  ld c,(hl) : inc hl : ld b,8
.bit:   rl c : jr nc,.sk
        ld a,(lg_c) : ld (de),a
.sk:    inc e : djnz .bit
        dec ixl : jr nz,.byte
        ld a,(lg_r) : inc a : ld (lg_r),a : cp 16 : jr c,.row
        ret
lg_c:   db 0
lg_x:   db 0
lg_y:   db 0
lg_r:   db 0
LOGO_PG equ 81                                      ; the logo bitmap has a page of its own (mapped at $C000 while it is drawn)

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
s_blk2: db "              ",0
; --- records just set: their rows use palette entry 42, which pulses
nw_tab:   ds 10
nw_trk:   db 255
hv_nw:    db 0
pl_on:    db 0
pl_t:     db 0
pl_c:     db 0
pcol:                                           ; A = normal colour -> colour 42 when the row being drawn is a new record
        ld b,a : ld a,(hv_nw) : or a : ld a,b : ret z
        ld a,42 : ret
nw_ins:                                         ; hi_r = place of a new record in the current track's table
        ld a,(nw_trk) : ld hl,track_idx : cp (hl) : jr z,.ok
        xor a : ld hl,nw_tab : ld de,nw_tab+1 : ld (hl),a : ld bc,9 : ldir
        ld a,(track_idx) : ld (nw_trk),a
.ok:    ld a,(hi_r) : ld e,a : ld a,9 : sub e : jr z,.s
        ld c,a : ld b,0 : ld hl,nw_tab+8 : ld de,nw_tab+9 : lddr
.s:     ld a,(hi_r) : ld e,a : ld d,0 : ld hl,nw_tab : add hl,de : ld (hl),1
        ld a,1 : ld (pl_on),a
        ret
pl_tick:                                        ; every 4th frame: colour 42 steps between orange and yellow
        ld a,(pl_on) : or a : ret z
        ld hl,pl_t : inc (hl) : ld a,(hl) : and 3 : ret nz
        ld a,(pl_c) : inc a : and 15 : ld (pl_c),a
        cp 8 : jr c,.u
        ld b,a : ld a,15 : sub b
.u:     add a,a : add a,a : or $E0 : ld b,a
        nextreg REG_PAL_IDX,42 : ld a,b : nextreg REG_PAL_VAL8,a
        ret
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
.dr:    ld a,32 : ld (sc_y),a
.row:   ld a,(sc_y) : ld b,a
        rlca : rlca : and 3 : add a,a : add a,18 : nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a
        ld a,b : and 63 : ld d,a : ld e,0
        ld a,(sc_off) : add a,b : cp 192 : jr nc,.blk
        ld c,a : rlca : rlca : and 3 : add a,a : add a,CLEAN_PG : nextreg REG_MMU2,a : inc a : nextreg REG_MMU3,a
        ld a,c : and 63 : or $40 : ld h,a : ld l,0
        ld bc,256 : ldir : jr .nx
.blk:   ld h,d : ld l,e : ld (hl),0 : inc de : ld bc,255 : ldir
.nx:    ld hl,sc_y : inc (hl) : ld a,(hl) : cp 152 : jr c,.row
        ret
ch_sel: db 0
ch_i:   db 0
ch_pv:  db 0
ch_tab: dw s_nt,s_nts,s_mm,s_mms
s_nt:   db "NEXT TRACK",0
s_nts:  db "> NEXT TRACK <",0
s_mm:   db "MAIN MENU",0
s_mms:  db "> MAIN MENU <",0

; ---- UPDATE TO ########: fetch the newer .nex beside the game; it is checked (NEX header, exact size) and the machine restarts
; The download may use memory the game is running in, so after it there is no going on: restart.
pg_update:
        call clear_screen
        ld a,3 : ld (txt_fg),a
        ld hl,s_ud1 : ld c,9 : call print_cen
        ld hl,s_ud2 : ld c,11 : call print_cen
        ld hl,s_ud3 : ld c,12 : call print_cen
        ld de,ud_fn : ld hl,s_udp : call nb_put                ; 3DSC3_########.NEX
        ld hl,upd_ver : ld bc,8 : ldir
        ld hl,s_ude : ld bc,5 : ldir
        ld de,nb : ld hl,s_c1 : call nb_put
        ld hl,net_host : call nb_put
        ld hl,s_cd : call nb_put
        ld hl,upd_line                                          ; "build,path,size,crc"
.a:     ld a,(hl) : inc hl : or a : jp z,ud_fail
        cp ',' : jr nz,.a
.p:     ld a,(hl) : or a : jp z,ud_fail
        cp ',' : jr z,.pe
        ld (de),a : inc hl : inc de : jr .p
.pe:    inc hl : push hl
        ld hl,s_cf : call nb_put
        ld hl,ud_fn : call nb_put
        ld a,13 : ld (de),a : inc de : xor a : ld (de),a
        pop hl
        ld (ud_sz),a : ld (ud_sz+1),a : ld (ud_sz+2),a          ; size in bytes, 24 bit
.d:     ld a,(hl) : sub '0' : cp 10 : jr nc,.dd
        ld b,a : inc hl : push hl
        ld a,(ud_sz) : ld d,a : ld e,10 : mul d,e
        ld a,b : add a,e : ld (ud_sz),a : ld a,d : adc a,0 : ld c,a
        ld a,(ud_sz+1) : ld d,a : ld e,10 : mul d,e
        ld a,c : add a,e : ld (ud_sz+1),a : ld a,d : adc a,0 : ld c,a
        ld a,(ud_sz+2) : ld d,a : ld e,10 : mul d,e
        ld a,c : add a,e : ld (ud_sz+2),a
        pop hl : jr .d
.dd:    ld a,(ud_sz) : ld b,a : ld a,(ud_sz+1) : or b : ld b,a : ld a,(ud_sz+2) : or b : jp z,ud_fail   ; no size
        call ud_unlink
        call net_exec : or a : jp nz,ud_fail
        ld b,1 : ld ix,ud_fn : call sv_open2 : jp c,ud_fail
        ld (sv_h),a
        ld ix,ud_buf : ld bc,4 : rst 8 : db $9D : jp c,ud_bad       ; a NEX file starts with "Next"
        ld hl,ud_buf : ld de,s_nx : ld b,4
.h:     ld a,(de) : cp (hl) : jp nz,ud_bad
        inc hl : inc de : djnz .h
        ld a,(ud_sz) : sub 1 : ld e,a : ld a,(ud_sz+1) : sbc a,0 : ld d,a
        ld a,(ud_sz+2) : sbc a,0 : ld c,a : ld b,0
        ld a,(sv_h) : ld l,0 : ld ix,0 : rst 8 : db $9F : jp c,ud_bad    ; the last byte must be there ...
        ld a,(sv_h) : ld ix,ud_buf : ld bc,1 : rst 8 : db $9D : jp c,ud_bad
        dec bc : ld a,b : or c : jp nz,ud_bad
        ld a,(sv_h) : ld ix,ud_buf : ld bc,1 : rst 8 : db $9D : jp c,ud_bad    ; ... and nothing after it
        ld a,b : or c : jp nz,ud_bad
        call sv_close
        call clear_screen
        ld a,3 : ld (txt_fg),a
        ld hl,s_ud4 : ld c,8 : call print_cen
        ld hl,ud_fn : ld c,10 : call print_cen
        ld hl,s_ud5 : ld c,12 : call print_cen
        ld a,PROMPT_C : ld (txt_fg),a
        ld hl,s_ud6 : ld c,15 : call print_cen
        ld bc,$00FE
.k0:    in a,(c) : cpl : and 31 : jr nz,.k0                     ; keys up
.k1:    in a,(c) : cpl : and 31 : jr z,.k1                      ; any key
        nextreg $02,1                                           ; soft reset
.hl:    jr .hl
ud_bad: call sv_close
ud_fail:
        call ud_unlink
        call clear_screen
        ld a,PROMPT_C : ld (txt_fg),a
        ld hl,s_ud7 : ld c,11 : call print_cen
        ld b,120
.w:     push bc : call wait_frame : pop bc : djnz .w
        ret
ud_unlink:
        nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF
        ld a,'*' : ld ix,ud_fn : rst 8 : db $AD : ret
s_udp:      db "3DSC3_",0
s_ude:      db ".NEX",0
s_nx:       db "Next"
s_ud1:      db "DOWNLOADING THE UPDATE",0
s_ud2:      db "THIS CAN TAKE A MINUTE",0
s_ud3:      db "PLEASE WAIT",0
s_ud4:      db "UPDATE DOWNLOADED",0
s_ud5:      db "LOAD IT TO PLAY THE NEW BUILD",0
s_ud6:      db "PRESS ANY KEY TO RESTART",0
s_ud7:      db "UPDATE FAILED",0
ud_fn:      ds 20
ud_sz:      ds 3
ud_buf:     ds 4
