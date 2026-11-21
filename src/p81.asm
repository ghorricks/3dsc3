; code and data that live in page 81 (mapped at $C000 while it runs; it calls only routines in main memory)
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
        ld a,20 : push hl : ld de,i1 : or a : sbc hl,de : pop hl : jr z,.c4      ; the two headings are green
        push hl : ld de,i5 : or a : sbc hl,de : pop hl : jr z,.c4
        ld a,4                                                                    ; the two credits stay yellow
        push hl : ld de,i12 : or a : sbc hl,de : pop hl : jr z,.c4
        push hl : ld de,i13 : or a : sbc hl,de : pop hl : jr z,.c4
        ld a,3                                                                    ; everything else white
.c4:    ld (txt_fg),a : call print_cen : pop bc : pop hl
        inc c : jr .l
.w:     ld a,PROMPT_C : ld (txt_fg),a : ld hl,i11 : ld c,23 : call print_cen
.wk:    call menu_in : or a : jr nz,.wk                ; let go of the key that brought us here
.w2:    call wait_frame : call menu_in : bit BST,a : jr z,.w2
.w3:    call wait_frame : call menu_in : bit BST,a : jr nz,.w3
        ret
; raw joystick ports, live (to find out which bits each stick really sends)
jdraw:  ld bc,$001F : in a,(c) : ld hl,jb1 : call jbits
        ld bc,$0037 : in a,(c) : ld hl,jb2 : call jbits
        ld bc,$243B : ld a,5 : out (c),a : inc b : in a,(c) : ld hl,jb3 : call jbits
        ld a,3 : ld (txt_fg),a
        ld b,8 : ld c,17 : ld hl,jt1 : call print_at
        ld b,8 : ld c,18 : ld hl,jt2 : call print_at
        ld b,8 : ld c,19 : ld hl,jt3 : call print_at
        ret
jbits:  ld d,a : ld b,8
.l:     ld a,'0' : rl d : adc a,0 : ld (hl),a : inc hl : djnz .l
        ret
jt1:    db "PORT 1F "
jb1:    ds 8
        db 0
jt2:    db "PORT 37 "
jb2:    ds 8
        db 0
jt3:    db "NEXTREG5 "
jb3:    ds 8
        db 0

; progress bar of the update download: UD_PART slices done of UD_NP
ud_bar: ld a,(ud_part) : ld hl,ud_np : cp (hl) : jr nz,.f
        ld a,192 : jr .g
.f:     ld d,a : ld a,(ud_step) : ld e,a : mul d,e : ld a,e
.g:     ld (ud_fill),a
        ld a,30 : ld (fr_x),a : ld a,100 : ld (fr_y),a : ld a,196 : ld (fr_w),a : ld a,12 : ld (fr_h),a
        ld a,3 : ld (fr_c),a : call fill_rect                   ; white frame
        ld a,32 : ld (fr_x),a : ld a,102 : ld (fr_y),a : ld a,192 : ld (fr_w),a : ld a,8 : ld (fr_h),a
        xor a : ld (fr_c),a : call fill_rect                    ; black inside
        ld a,(ud_fill) : or a : jr z,.nf
        ld (fr_w),a : ld a,32 : ld (fr_x),a : ld a,102 : ld (fr_y),a : ld a,8 : ld (fr_h),a
        ld a,20 : ld (fr_c),a : call fill_rect                  ; green: what is done
.nf:
        ret
ud_fill: db 0

; ---- DEBUG on / off: Symbol Shift + D on the main menu. A red D after the version number shows it is on; it unlocks all the extra tracks (26, 27).
dbg_dn: db 0
pg_dbgk:
        call sc_tick                                                    ; the scrolling message line
        ld bc,$7FFE : in a,(c) : bit 1,a : jr nz,.up                    ; Symbol Shift down?
        ld bc,$FDFE : in a,(c) : bit 2,a : jr nz,.up                    ; and D?
        ld a,(dbg_dn) : or a : ret nz                                   ; only a new press counts
        inc a : ld (dbg_dn),a
        ld a,(dbg_viz) : xor 1 : ld (dbg_viz),a
        ld b,25 : jr z,.off
        ld b,27
.off:   ld a,b : ld (trk_max),a
        cp 26 : jr nc,.mk                                               ; off: a track of the extra ones is not on offer any more
        ld a,(track_idx) : cp 25 : jr c,.mk
        xor a : ld (track_idx),a
.mk:    jp dbg_mark
.up:    xor a : ld (dbg_dn),a : ret
dbg_mark:                                                               ; a red D (or a blank) after the version number, bottom centre of the menu
        ld a,(dbg_viz) : or a : ld hl,s_dd : ld a,24 : jr nz,.p
        ld hl,s_dn : ld a,3
.p:     ld (txt_fg),a : ld b,25 : ld c,23 : call print_at
        ld a,3 : ld (txt_fg),a : ret
s_dd:   db "D",0
s_dn:   db " ",0

; nine level bars, one per tune channel, bottom left of the menu screens.
; blue = AY 1 (A B C), green = AY 2, red = AY 3; a bar is as tall as the channel's volume (0-15)
VZ_Y        equ 159                                         ; bars' baseline row = bottom of the START GAME line
vz_i:       db 0
vz_v:       db 0
vz_off:     db 8,9,10, 24,25,26, 40,41,42                   ; the channel's volume register in mus_sh
vz_x:       db 2,7,12, 19,24,29, 36,41,46
vz_c:       db 16,16,16, 20,20,20, 24,24,24
mus_viz:
        ld a,(ttl_on) : or a : ret nz                       ; the title picture is up: no bars, no car
        call idle_tick
        ld a,(vj_on) : or a : jp nz,vj_step                 ; racing: only the jingle
        xor a : ld (vz_i),a
.l:     ld a,(vz_i) : ld e,a : ld d,0
        ld hl,vz_off : add hl,de : ld a,(hl) : ld hl,mus_sh : add a,l : ld l,a
        ld a,(hl) : and 15 : ld (vz_v),a
        ld hl,vz_x : add hl,de : ld a,(hl) : ld (fr_x),a
        ld a,VZ_Y : ld (fr_y),a : ld a,4 : ld (fr_w),a : ld a,16 : ld (fr_h),a : xor a : ld (fr_c),a : call fill_rect
        ld a,(vz_i) : ld e,a : ld d,0
        ld a,(vz_v) : or a : jr z,.bl
        ld b,a : ld a,VZ_Y+16 : sub b : ld (fr_y),a : ld a,b : ld (fr_h),a
        ld hl,vz_c : add hl,de : ld a,(hl) : ld (fr_c),a : ld a,4 : ld (fr_w),a : call fill_rect
        ld a,(vz_i) : ld e,a : ld d,0
.bl:    ld hl,vz_x : add hl,de : ld a,(hl) : ld (fr_x),a
        ld a,VZ_Y+16 : ld (fr_y),a : ld a,1 : ld (fr_h),a : ld a,5 : ld (fr_c),a : ld a,4 : ld (fr_w),a : call fill_rect
        ld a,(vz_i) : inc a : ld (vz_i),a : cp 9 : jp nz,.l
        jp pg_car
vj_step:ld hl,vj_back : push hl : jp mus_isr                ; run one 50 Hz frame of the tune code by hand: its 'ei : reti' returns here
vj_back:di : ret


; the big stock car (menu screens, bottom right): picture from build/bigcar.bin = w,h then one byte per pixel (0 clear, 1-4 body shades, 5-8 fixed)
VC_X        equ 210
VC_Y        equ 149
vc_lut:     ds 10
vc_w:       db 0
vc_h:       db 0
vc_y:       db 0
pg_car:     ld a,(vz_car) : and 3 : add a,a : add a,a : add a,15 : ld c,a            ; blue, green, red, yellow in turn
            ld hl,vc_lut : xor a : ld (hl),a : inc hl
            ld a,c : inc a : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl
            ld a,8 : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl : inc a : ld (hl),a : inc hl : inc a : ld (hl),a
            inc hl : ld a,12 : ld (hl),a                                  ; 9 = hubcap
            exx : ld hl,vc_lut : exx
            ld hl,bigcar : ld a,(hl) : ld (vc_w),a : inc hl : ld a,(hl) : ld (vc_h),a : inc hl
            ld a,VC_Y : ld (vc_y),a
.row:       ld a,(vc_y) : ld e,VC_X : call l2_row_addr
            ld a,(vc_w) : ld b,a
.px:        ld a,(hl) : inc hl : or a : jr z,.sk
            exx : ld c,a : ld b,0 : push hl : add hl,bc : ld a,(hl) : pop hl : exx : ld (de),a
.sk:        inc e : djnz .px
            ld a,(vc_y) : inc a : ld (vc_y),a
            ld a,(vc_h) : dec a : ld (vc_h),a : jr nz,.row
            ret
bigcar:     INCBIN "build/bigcar.bin"

; ---- title picture (6 pages of 8 KB, 32 rows each, default RGB332 palette) and the idle timer of the main menu
ttl_on:     db 0
idle_en:    db 0
idle_vz:    db 0
idle_cnt:   dw 0
ty:         db 0
tk:         db 0
pg_mhead:   call init_hw                                     ; game palette back (the title picture sets its own)
            ld a,3 : ld (txt_fg),a
            ld a,(sc_st) : dec a : jr nz,.cr                 ; messages already under way: carry on (redraw the strip as it was), never back to the credit
            ld a,(sc_s) : ld l,a : ld a,(sc_s+1) : ld h,a
            ld de,256 : or a : sbc hl,de                     ; HL = first column on screen (negative = blank)
            ld c,0
.rs:        push hl : push bc : call sc_dc : pop bc : pop hl : inc hl : inc c : jr nz,.rs
            jr .cd
.cr:        call by_draw                                     ; By Gavin Horricks (mixed case strip, one character right of the old centring)
            xor a : ld (sc_st),a : ld (sc_t),a              ; the message line starts again from the credit
.cd:
            ld a,3 : ld (txt_fg),a                           ; bottom centre: VERSION : build
            ld b,7 : ld c,23 : ld hl,s_vlab : call print_at
            ld b,17 : ld c,23 : ld hl,s_ver : call print_at
            call dbg_mark                                    ; the red D when DEBUG is on
            ld a,(vz_car) : ld (idle_vz),a                   ; this screen: if another one is drawn the timer disarms itself
            ld a,1 : ld (idle_en),a
            ld hl,0 : ld (idle_cnt),hl
            xor a : ld (idle_go),a
            ret
idle_tick:  ld a,(idle_en) : or a : ret z
            ld a,(vz_car) : ld hl,idle_vz : cp (hl) : jr z,.s
            xor a : ld (idle_en),a : ret
.s:         push bc : push de : push hl
            call menu_in : or a : jr nz,.r                   ; any key or joystick: start counting again
            ld hl,(idle_cnt) : inc hl : ld (idle_cnt),hl
            ld de,1000 : or a : sbc hl,de : jr c,.o          ; 1000 frames = 20 s
            ld a,1 : ld (idle_go),a : xor a : ld (idle_en),a
            jr .o
.r:         ld hl,0 : ld (idle_cnt),hl
.o:         pop hl : pop de : pop bc
            ret
pg_title:   push af
            nextreg REG_PAL_CTRL,$10                         ; Layer 2 first palette: the plain RGB332 ramp the picture was drawn for
            ld b,0 : xor a
.pp:        nextreg REG_PAL_IDX,a : nextreg REG_PAL_VAL8,a : inc a : djnz .pp
            ld a,TITLE_PG : nextreg REG_MMU7,a : ld hl,$E000
            xor a : ld (tk),a
.pg:        ld a,(tk) : add a,a : add a,18 : nextreg REG_MMU0,a : inc a : nextreg REG_MMU1,a      ; Layer 2 bank k (16 KB) at $0000
            ld a,(tk) : cp 2 : jr nz,.sm
            ld a,TITLE_PG+1 : nextreg REG_MMU7,a : ld hl,$E000                                   ; the third bank's stream is in the second page
.sm:        ld de,0 : call lz_dec
            ld a,(tk) : inc a : ld (tk),a : cp 3 : jr c,.pg
            pop af : or a : ret z                            ; start-up: leave it on screen
            ld a,1 : ld (ttl_on),a
            ld hl,500                                        ; 10 s, or any key
.h:         push hl : call wait_frame : call menu_in : pop hl : or a : jr nz,.x
            dec hl : ld a,h : or l : jr nz,.h
.x:         xor a : ld (ttl_on),a
            ret
lz_dec:     ld ixl,$80                                        ; bit buffer empty
.l:         call .gb : jr nc,.m
            ld a,(hl) : inc hl : ld (de),a : inc de             ; literal
            jr .c
.m:         ld c,(hl) : inc hl : ld b,(hl) : inc hl             ; match: offset low, offset high nibble | length-3
            push hl
            ld a,b : and $F0 : rrca : rrca : rrca : rrca : ld h,a : ld l,c
            ld a,b : and 15 : add a,3 : ld c,a : ld b,0
            push de : ex de,hl : or a : sbc hl,de : pop de      ; HL = dest - offset
            ldir : pop hl
.c:         ld a,d : cp $40 : jr c,.l                          ; one 16 KB bank done
            ret
.gb:        ld a,ixl : add a,a : jr nz,.g1
            ld a,(hl) : inc hl : rla
.g1:        ld ixl,a : ret

by_draw:                                                     ; 17 cells x 8 rows at x=64, y=24, white
            ld hl,by_bmp : xor a : ld (by_r),a
.row:       push hl
            ld a,(by_r) : add a,24 : ld e,64 : call l2_row_addr
            pop hl : ld b,17
.byte:      ld c,(hl) : inc hl : push bc : ld b,8
.bit:       rl c : jr nc,.sk
            ld a,3 : ld (de),a
.sk:        inc e : djnz .bit
            pop bc : djnz .byte
            ld a,(by_r) : inc a : ld (by_r),a : cp 8 : jr c,.row
            ret
by_r:       db 0
by_bmp:     INCBIN "build/byline.bin"

; ---- the scrolling message line (y 24-31, under the title): "By Gavin Horricks" stays for 2 seconds, then the messages from the server push it
; off to the left, 2 pixels a frame; when the last one has gone the credit is drawn again and the cycle repeats.
sc_st:  db 0                                                    ; 0 credit shown (waiting), 1 scrolling
sc_t:   db 0
sc_s:   dw 0                                                    ; pixels of the message already pushed in
sc_lpx: dw 0                                                    ; length of the message text in pixels
sc_k:   db 0
sc_r:   db 0
sc_tick:
        IFDEF SCTEST
        ld a,(sc_st) : cp 2 : ret z
        ld a,(msg_buf) : or a : ret z
        ld hl,msg_buf : ld de,0
.tc:    ld a,(hl) : or a : jr z,.td
        inc hl : inc de : jr .tc
.td:    ex de,hl : add hl,hl : add hl,hl : add hl,hl : ld (sc_lpx),hl
        ld hl,0
.tl:    push hl : ld a,l : add a,60 : ld c,a : call sc_dc : pop hl : inc hl : ld a,l : cp 120 : jr c,.tl
        ld a,2 : ld (sc_st),a : ret
        ENDIF
        ld a,(sc_st) : or a : jr nz,.run
        ld a,(msg_buf) : or a : ret z                           ; nothing to show
        ld hl,sc_t : inc (hl) : ld a,(hl) : cp 100 : ret c      ; 2 seconds of the credit
        ld a,1 : ld (sc_st),a
        ld hl,0 : ld (sc_s),hl
        ld hl,msg_buf : ld de,0
.l:     ld a,(hl) : or a : jr z,.d
        inc hl : inc de : jr .l
.d:     ex de,hl : add hl,hl : add hl,hl : add hl,hl : ld (sc_lpx),hl
        ret
.run:   call sc_shift
        ld hl,(sc_s) : ld c,254 : call sc_dc
        ld hl,(sc_s) : inc hl : ld c,255 : call sc_dc
        ld hl,(sc_s) : inc hl : inc hl : ld (sc_s),hl
        ld hl,(sc_lpx) : ld de,256 : add hl,de : ex de,hl             ; DE = pixels after which the last message has left the screen
        ld hl,(sc_s) : or a : sbc hl,de : ret c
        ld hl,0 : ld (sc_s),hl                                        ; keep going: the messages come round again (no return to the credit)
        ret
sc_shift:                                                       ; the 8 rows of the strip 2 pixels to the left
        xor a : ld (sc_r),a
.r:     ld a,(sc_r) : add a,24 : ld e,0 : call l2_row_addr
        ld h,d : ld l,e : inc hl : inc hl : ld bc,254 : ldir
        ld a,(sc_r) : inc a : ld (sc_r),a : cp 8 : jr c,.r
        ret
sc_dc:                                                          ; HL = column of the message text, C = screen x: draws its 8 pixels (blank beyond the text)
        push hl : ld de,(sc_lpx) : or a : sbc hl,de : pop hl : jr nc,.bl
        ld a,l : and 7 : ld (sc_k),a
        srl h : rr l : srl h : rr l : srl h : rr l
        ld h,0 : ld de,msg_buf : add hl,de : ld a,(hl)
        sub 32 : jr c,.sp : cp 64 : jr c,.ok
.sp:    xor a
.ok:    ld l,a : ld h,0 : add hl,hl : add hl,hl : add hl,hl : ld de,font : add hl,de
        xor a : ld (sc_r),a
.r:     ld a,(sc_k) : ld b,a : ld a,(hl) : inc b : jr .e
.s:     add a,a
.e:     djnz .s
        and $80 : ld a,0 : jr z,.q
        ld a,4
.q:     ld b,a : push hl : ld a,(sc_r) : add a,24 : ld e,c : call l2_row_addr : ld a,b : ld (de),a : pop hl : inc hl
        ld a,(sc_r) : inc a : ld (sc_r),a : cp 8 : jr c,.r
        ret
.bl:    xor a : ld (sc_k),a : jr .ok
msg_buf:    ds 504                                          ; the scrolling messages from the server (up to 500 characters, 0-terminated; empty = none)
