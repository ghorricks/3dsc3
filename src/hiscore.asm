; ===================================================================== best laps + online scores
; Lives in RAM page HS_PG, which is mapped at $E000 while any of this runs (the stubs in main.asm map it).
; $E000-$EF9F: 25 tracks x 20 entries x 8 bytes: name (5), time in hundredths of a second (2), synced flag (1 = on the server).
; Code from $EFC0. Name entry, panels and the end-of-race choice are in the second page (hiscore_b.asm, HS_PGB at $C000).  Local table is saved to 3DSC3.SAV; new records are sent to the online table with the .http dot command.
HS_ENT      equ $E000

pg_init:                                            ; every record starts as 3DSC3 99.9S
        ld de,HS_ENT : ld a,250
.l:     push af : ld hl,hs_def : ld bc,8 : ldir : pop af : dec a : jr nz,.l
        ld a,250
.l2:    push af : ld hl,hs_def : ld bc,8 : ldir : pop af : dec a : jr nz,.l2          ; 25 tracks x 20 entries = 500
        ld hl,pn_def : ld de,pn_tab : ld bc,20 : ldir
        xor a : ld (HS_MARK),a
        xor a : ld (sv_n),a : ld (sv_n+1),a
        call sv_load                                ; records and player names saved by an earlier session
        ld hl,(sv_n) : ld de,4021 : or a : sbc hl,de : jr z,.nm   ; this build's save: 25 x 20 entries + 20 name bytes + marker
        ld hl,(sv_n) : ld de,1941 : or a : sbc hl,de : jr nz,.o10 ; a 24-track save (1941 bytes): names + marker sit behind track 24, track 25 is new
        ld hl,HS_ENT+1920 : ld de,pn_mv : ld bc,21 : ldir
        ld de,HS_ENT+1920 : ld a,10
.t25:   push af : ld hl,hs_def : ld bc,8 : ldir : pop af : dec a : jr nz,.t25
        jr .sp
.o10:   ld hl,(sv_n) : ld de,2021 : or a : sbc hl,de : jr nz,.nm  ; (anything else is not a save of ours: defaults stay)
        ld hl,HS_ENT+2000 : ld de,pn_mv : ld bc,21 : ldir        ; a 10-entry save: names and marker out of the way, the tables spread out to 20 entries
.sp:    call hs_spread
        ld hl,pn_mv : ld de,HS_NAMES : ld bc,21 : ldir
.nm:
        call hs_mig
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
hs_mig:     ld a,(HS_MARK) : or a : ret nz                   ; an older save: every time gets a zero appended (tenths -> hundredths)
            inc a : ld (HS_MARK),a
            ld ix,HS_ENT+5 : ld c,2
.m0:        ld b,250
.m:         ld l,(ix+0) : ld h,(ix+1) : ld de,999 : or a : sbc hl,de : jr nc,.d
            add hl,de : ld d,h : ld e,l : add hl,hl : add hl,hl : add hl,de : add hl,hl
            jr .s
.d:         ld hl,9999
.s:         ld (ix+0),l : ld (ix+1),h
            ld de,8 : add ix,de : djnz .m
            dec c : jr nz,.m0
            ret
hs_spread:                                                   ; 25 tracks of 10 entries -> 25 tracks of 20, from the last track down; the new places are blank records
            ld a,24
.t:         ld (hsp_t),a
            ld d,a : ld e,80 : mul d,e : ld hl,HS_ENT : add hl,de : push hl
            ld a,(hsp_t) : ld d,a : ld e,160 : mul d,e : ld hl,HS_ENT : add hl,de : ex de,hl : pop hl
            ld bc,80 : ldir
            ld b,10
.f:         push bc : ld hl,hs_def : ld bc,8 : ldir : pop bc : djnz .f
            ld a,(hsp_t) : or a : ret z
            dec a : jr .t
hsp_t:      db 0
pn_mv:      ds 21
hs_def: db "3DSC3",$0F,$27,1
HS_MARK     equ HS_ENT+4020                         ; 1 = the saved times are in hundredths (older saves hold tenths)
HS_NAMES    equ HS_ENT+4000                         ; the four players' names (5 character indices each) are saved with the table
pn_tab      equ HS_NAMES
pn_def:     db 0,36,36,36,36, 0,36,36,36,36, 0,36,36,36,36, 0,36,36,36,36     ; just an "A" until a player types a name

hs_ptr:                                             ; -> HL = first entry of the current track (track 26, DEBUG only, has no saved table: a blank one in page 93)
        ld a,(track_idx) : cp 25 : jr c,.o : ld hl,t26_tab : ret
.o:
     ld d,a : ld e,160 : mul d,e : ld hl,HS_ENT : add hl,de
        ret

hs_rank:                                            ; DE = hundredths -> A = place 0..19, or 20 when it does not make the table
        ld a,(track_idx) : cp 25 : ld a,20 : ret nc                 ; track 26: no records

        push de : call hs_ptr : push hl : pop ix : pop de
        xor a : ld (hr_i),a
.l:     ld c,(ix+5) : ld b,(ix+6) : ld h,d : ld l,e : or a : sbc hl,bc : jr c,.f
        ld bc,8 : add ix,bc : ld a,(hr_i) : inc a : ld (hr_i),a : cp 20 : jr c,.l
.f:     ld a,(hr_i)
        ret
hr_i:   db 0

hs_insert:                                          ; A = place, DE = tenths, name in hn_buf
        ld (hi_r),a : ld (hi_t),de
        push de : call nw_ins : pop de                 ; remember which entries are new (they pulse in the table)
        ld a,(hi_r) : ld b,a : ld a,19 : sub b : ld d,a : ld e,8 : mul d,e : ld b,d : ld c,e     ; BC = bytes to move down
        call hs_ptr : ld de,151 : add hl,de : push hl : ld de,8 : add hl,de : ex de,hl : pop hl
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
        ld h,d : ld l,e : ld bc,9999 : or a : sbc hl,bc : jr nc,.n                   ; no lap time
        ld (hi_t),de
        call hs_rank
        cp 20 : jr nc,.n
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
        ld de,(hi_t) : call hs_rank : cp 20 : ret nc
        ld de,(hi_t) : jp hs_insert

charset: db "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "

; ===================================================================== online (.http dot command, plain HTTP)
NET_BANK    equ 41                                  ; 16K bank (8K pages 82/83) that receives the reply
NET_PG      equ 82
net_host:   db "3dsc3.silent-cloud-35d4.workers.dev",0
s_c1:       db ".http -h ",0
s_c5:       db " -f 3DSC3.TMP",0
s_c2:       db " -u /?track=",0
s_all:      db "all&n=20",0
nb_all:     db 0
nb_ver:     db 0
s_cv:       db " -u /?version",0
s_cd:       db " -u /?download=",0
s_cf:       db " -f ",0
s_chk:      db "CHECKING FOR UPDATES...",0

; --- once at start: the server's version.txt ("26111830,releases/....nex,size,crc") says which build is newest
pg_vcheck:
        xor a : ld (upd_flag),a
        call ck_msg                                        ; CHECKING FOR UPDATES... on a black panel, bottom right (the title picture or the menu stays untouched elsewhere)
        ld a,1 : ld (nb_ver),a
        call net_clear : call nb_base : call nb_end
        call net_try                                       ; one attempt only: nobody should wait long for this
        ld b,a : xor a : ld (nb_ver),a
        ld a,b : or a : ret nz
        nextreg REG_MMU6,NET_PG
        call msg_grab                                       ; line 2 of the reply = the scrolling messages (old servers send none)
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
            ld hl,s_all : jp nb_put                            ; ?track=all&n=20: the best 20 of every table in one reply
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

msg_grab:                                                       ; the reply is at $C000: skip line 1, keep line 2 (up to 500 characters) in msg_buf (page 81)
        ld hl,$C000 : ld b,255
.f:     ld a,(hl) : inc hl : cp 10 : jr z,.g
        or a : jr z,.n
        djnz .f
.n:     nextreg REG_MMU6,LOGO_PG : xor a : ld (msg_buf),a : nextreg REG_MMU6,NET_PG
        ret
.g:     ld de,msg_buf : ld (mg_d),de : ld a,4
.k:     ld (mg_c),a
        ld de,nb : ld bc,125 : ldir                                ; a piece through main memory (the two pages cannot be mapped together)
        push hl
        nextreg REG_MMU6,LOGO_PG
        ld hl,nb : ld de,(mg_d) : ld bc,125 : ldir : ld (mg_d),de
        nextreg REG_MMU6,NET_PG
        pop hl
        ld a,(mg_c) : dec a : jr nz,.k
        nextreg REG_MMU6,LOGO_PG : ld hl,(mg_d) : ld (hl),0 : nextreg REG_MMU6,NET_PG
        ret
mg_d:   dw 0
mg_c:   db 0
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
.use:       ld a,(oc_ok) : or a : jr z,.none
            ld a,(track_idx) : ld e,a : ld d,0
            ld hl,oc_cnt : add hl,de : ld a,(hl) : push af
            call oc_adr                                        ; HL = this track's block in the cache page
            nextreg REG_MMU6,OC_PG
            ld de,oc_cur : ld bc,160 : ldir                    ; a copy in this page: the cache page is only mapped for a moment
            nextreg REG_MMU6,HS_PGB
            ld hl,oc_cur : pop af : ret
.none:      nextreg REG_MMU6,HS_PGB
            ld hl,oc_cur : xor a : ret
oc_adr:                                                         ; E = track 0..24 (D = 0) -> HL = $C000 + 160 * track
            ld h,d : ld l,e : add hl,hl : add hl,hl : add hl,de
            add hl,hl : add hl,hl : add hl,hl : add hl,hl : add hl,hl
            ld de,$C000 : add hl,de : ret
oc_cur:     ds 160
oc_cnt:     ds 25
np_buf:     ds 8
net_run:    call net_try : ret z                                ; A = 0 when a reply arrived
            ld a,(nb_all) : or a : call nz,net_retry                ; the machine is busy inside the WiFi command (nothing can animate): say it is trying again
            call net_try                                       ; the WiFi module sometimes drops a request: once more
            or a : ret
net_wipe:   xor a : ld (fr_x),a : ld (fr_c),a : ld a,96 : ld (fr_y),a : ld a,255 : ld (fr_w),a : ld a,8 : ld (fr_h),a
            jp fill_rect
net_retry:  ld a,6 : ld (txt_fg),a                              ; second attempt: the same message again in another colour
            ld hl,s_wait : ld c,12 : jp print_cen
net_try:    call net_unlink                                    ; old reply out of the way
            call net_exec : or a : jr nz,.e
            nextreg REG_MMU6,NET_PG
            call net_rd
            push af : call net_unlink : pop af                 ; the reply is in memory: no scratch file left on the card
            or a
.e:         ret
net_unlink: nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF
            ld a,'*' : ld ix,tmp_name : rst 8 : db $AD : ret
net_rd:     ld b,1 : ld ix,tmp_name : call sv_open2 : jr nc,.o
            ld (net_err),a : ld a,2 : ld (net_stage),a : ld a,1 : ret
.o:
            ld (sv_h),a : ld ix,$C000 : ld bc,8000 : rst 8 : db $9D : ld (net_len),bc : call sv_close
            ld hl,$C000 : ld bc,(net_len) : add hl,bc : ld (hl),0                        ; end of text
            ld a,($C000) : or a : jr z,.f
            xor a : ret
.f:         ld a,3 : ld (net_stage),a : ld a,1 : ret
tmp_name:   db "3DSC3.TMP",0

; --- parse the ?track=all reply: "T,NAME,42.37" lines at $C000 (page 82) into the cache (page 83: 20 x 8 bytes per track; the counts are in oc_cnt)
OC_PG       equ 83
net_parse:  ld hl,oc_cnt : ld de,oc_cnt+1 : ld bc,24 : ld (hl),0 : ldir
            ld hl,$C000
.ln:        ld a,(hl) : or a : ret z
            ld (np_ln),hl : ld d,0
.td:        ld a,(hl) : cp ',' : jr z,.tk
            sub '0' : cp 10 : jr nc,.sk
            ld e,a : ld a,d : add a,a : ld c,a : add a,a : add a,a : add a,c : add a,e : ld d,a
            inc hl : jr .td
.tk:        inc hl : ld a,d : or a : jr z,.sk
            dec a : cp 25 : jr nc,.sk
            ld (np_t),a : ld e,a : ld d,0
            push hl : ld hl,oc_cnt : add hl,de : ld a,(hl) : pop hl
            cp 20 : jr nc,.sk                                  ; the table of a track holds 20 records
            ld (np_c),a
            ld de,np_buf
            call np_rec : jr c,.sk
            ld a,(np_t) : ld e,a : ld d,0 : call oc_adr        ; HL = the track's block
            ld a,(np_c) : add a,a : add a,a : add a,a : ld e,a : ld d,0 : add hl,de
            ex de,hl : ld hl,np_buf : ld bc,8
            nextreg REG_MMU6,OC_PG : ldir : nextreg REG_MMU6,NET_PG
            ld a,(np_t) : ld e,a : ld d,0 : ld hl,oc_cnt : add hl,de : inc (hl)
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
.fr:        inc hl : ld a,(hl) : sub '0' : cp 10 : jr nc,.z       ; two decimals: seconds -> hundredths
            call add_dig : inc hl : ld a,(hl) : sub '0' : cp 10 : jr c,.t2
.z:         xor a
.t2:        call add_dig
            ld h,b : ld l,c
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
.tr:        ld b,20
.en:        ld a,(ix+7) : or a : jr nz,.nx
            ld l,(ix+5) : ld h,(ix+6) : ld de,9999 : or a : sbc hl,de : jr nc,.nx          ; default 99.99 entries are not scores
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
            ld hl,ns_t : inc (hl) : ld a,(hl) : cp 25 : jp c,.tr
.end:       nextreg REG_MMU6,HS_PGB                              ; the second page back (net_show lives there)
            ld a,(sy_fail) : or a : jr z,.sv
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
            ld bc,1000 : call nb_dg : ld bc,100 : call nb_dg
            ld a,'.' : ld (de),a : inc de
            ld bc,10 : call nb_dg
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
            ld (sv_h),a : ld ix,HS_ENT : ld bc,4021 : rst 8 : db $9D : ld (sv_n),bc : jr sv_close
sv_save:    ld b,$0E : call sv_open : ret c                   ; write, create or truncate
            ld (sv_h),a : ld ix,HS_ENT : ld bc,4021 : rst 8 : db $9E
sv_close:   ld a,(sv_h) : rst 8 : db $9B : ret
sv_h:       db 0
sv_n:       dw 0                                              ; bytes read from the save file
sv_name:    db "3DSC3.SAV",0





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

; --- records just set: their rows use palette entry 42, which pulses
nw_tab:   ds 20
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
        xor a : ld hl,nw_tab : ld de,nw_tab+1 : ld (hl),a : ld bc,19 : ldir
        ld a,(track_idx) : ld (nw_trk),a
.ok:    ld a,(hi_r) : ld e,a : ld a,19 : sub e : jr z,.s
        ld c,a : ld b,0 : ld hl,nw_tab+18 : ld de,nw_tab+19 : lddr
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

; ---- UPDATE TO ########: fetch the newer .nex beside the game; it is checked (NEX header, exact size) and the machine restarts
; The download may use memory the game is running in, so after it there is no going on: restart.
pg_update:
        call clear_screen
        ld a,3 : ld (txt_fg),a
        ld hl,s_ud1 : ld c,9 : call print_cen
        ld hl,s_ud3 : ld c,18 : call print_cen
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
        ld hl,s_cp : call nb_put                                ; "&part=" - the digit and the file go on per slice
        ld (ud_dpos),de
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
        ld hl,(ud_sz) : ld a,(ud_sz+2) : ld c,a : ld b,0         ; slices of 60928 bytes: how many?
.np:    inc b : ld de,60928 : or a : sbc hl,de : ld a,c : sbc a,0 : ld c,a : jr c,.nd
        ld a,h : or l : or c : jr nz,.np
.nd:    ld a,b : ld (ud_np),a : cp 24 : jp nc,ud_fail
        ld a,192 : ld d,0
.q:     cp b : jr c,.qd
        sub b : inc d : jr .q
.qd:    ld a,d : ld (ud_step),a                                 ; bar pixels per slice
        xor a : ld (ud_part),a
        call ud_unlink
.lp:    nextreg REG_MMU6,LOGO_PG : call ud_bar                  ; progress bar (code in page 81)
        ld hl,(ud_dpos) : ld a,(ud_part) : add a,'0' : ld (hl),a : inc hl : ex de,hl
        ld hl,s_csl : call nb_put
        ld a,13 : ld (de),a : inc de : xor a : ld (de),a
        call ud_unl_slc
        call net_exec : or a : jp nz,ud_fail
        call ud_append : jp c,ud_fail
        ld hl,ud_part : inc (hl) : ld a,(hl) : ld hl,ud_np : cp (hl) : jr c,.lp
        call ud_unl_slc
        nextreg REG_MMU6,LOGO_PG : call ud_bar                  ; full bar
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
        ld hl,ud_fn : ld (ud_show),hl
        call ud_unlink_old                                      ; 3DSC3.OLD out of the way
        ld ix,ud_nex : ld de,ud_old : call ud_ren               ; the current 3DSC3.NEX (if that is its name) becomes 3DSC3.OLD
        ld a,0 : rla : xor 1 : ld (ud_had),a                    ; 1 = there was one, now 3DSC3.OLD
        ld ix,ud_fn : ld de,ud_nex : call ud_ren                ; the new one becomes 3DSC3.NEX
        jr c,.nr
        ld hl,ud_nex : ld (ud_show),hl
        call ud_unlink_old                                      ; and the old one is deleted
        jr .rd
.nr:    ld a,(ud_had) : or a : jr z,.rd                          ; could not rename: put the old one back, show the long name
        ld ix,ud_old : ld de,ud_nex : call ud_ren
.rd:
        call clear_screen
        ld a,3 : ld (txt_fg),a
        ld hl,s_ud4 : ld c,8 : call print_cen
        ld hl,(ud_show) : ld c,10 : call print_cen
        ld hl,s_ud5 : ld c,12 : call print_cen
        ld a,PROMPT_C : ld (txt_fg),a
        ld hl,s_ud6 : ld c,15 : call print_cen
.k0:    call ud_any : jr nz,.k0                                 ; everything up
.k1:    call ud_any : jr z,.k1                                  ; any key or fire
        nextreg $02,1                                           ; soft reset
.hl:    jr .hl
ud_bad: call sv_close
ud_fail:
        call ud_unlink : call ud_unl_slc
        call clear_screen
        ld a,PROMPT_C : ld (txt_fg),a
        ld hl,s_ud7 : ld c,11 : call print_cen
        ld b,120
.w:     push bc : call wait_frame : pop bc : djnz .w
        ret
ud_any: ld bc,$00FE : in a,(c) : cpl : and 31 : ret nz                  ; NZ when a key or a pad button is down
        call menu_in : and 1<<BST : ret
ud_ren:                                                         ; IX = from, DE = to -> carry on failure
        nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF
        ld a,'*' : rst 8 : db $B0 : ret
ud_unlink_old:
        nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF
        ld a,'*' : ld ix,ud_old : rst 8 : db $AD : ret
ud_nex:     db "3DSC3.NEX",0
ud_old:     db "3DSC3.OLD",0
ud_show:    dw 0
ud_had:     db 0
ud_append:                                                      ; the slice file is added to the new file at part * 60928
        ld b,1 : ld ix,ud_slc : call sv_open2 : ret c
        ld (ud_h1),a
        ld a,(ud_part) : or a : ld b,$0E : jr z,.o
        ld b,$0A
.o:     ld ix,ud_fn : call sv_open2 : jr c,.e1
        ld (ud_h2),a
        ld a,(ud_part) : or a : jr z,.cp
        ld d,a : ld e,$EE : mul d,e : ld c,d : ld d,e : ld e,0 : ld b,0
        ld a,(ud_h2) : ld l,0 : ld ix,0 : rst 8 : db $9F : jr c,.e2
.cp:    nextreg REG_MMU6,NET_PG
.l:     ld a,(ud_h1) : ld ix,$C000 : ld bc,8192 : rst 8 : db $9D : jr c,.e2
        ld a,b : or c : jr z,.ok
        ld a,(ud_h2) : ld ix,$C000 : rst 8 : db $9E : jr c,.e2
        jr .l
.ok:    ld a,(ud_h2) : rst 8 : db $9B
        ld a,(ud_h1) : rst 8 : db $9B
        or a : ret
.e2:    ld a,(ud_h2) : rst 8 : db $9B
.e1:    ld a,(ud_h1) : rst 8 : db $9B
        scf : ret
ud_unl_slc:
        nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF
        ld a,'*' : ld ix,ud_slc : rst 8 : db $AD : ret
s_cp:       db "&part=",0
s_csl:      db " -f 3DSC3.SLC",0
ud_slc:     db "3DSC3.SLC",0
ud_dpos:    dw 0
ud_np:      db 0
ud_part:    db 0
ud_step:    db 0
ud_h1:      db 0
ud_h2:      db 0
ud_unlink:
        nextreg REG_MMU0,$FF : nextreg REG_MMU1,$FF
        ld a,'*' : ld ix,ud_fn : rst 8 : db $AD : ret
s_udp:      db "3DSC3_",0
s_ude:      db ".NEX",0
s_nx:       db "Next"
s_ud1:      db "DOWNLOADING THE UPDATE",0
s_ud3:      db "DO NOT SWITCH OFF",0
s_ud4:      db "UPDATE DOWNLOADED",0
s_ud5:      db "LOAD IT TO PLAY THE NEW BUILD",0
s_ud6:      db "PRESS ANY KEY OR FIRE TO EXIT",0
s_ud7:      db "UPDATE FAILED",0
