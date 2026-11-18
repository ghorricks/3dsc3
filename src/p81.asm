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
        ld a,4
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
