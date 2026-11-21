; ---- Input: M30 / Megadrive pads + keyboard fallback ----
; NOTE: bit layout for MD mode taken from my memory of the Next manual;
; could not be verified online here. See README "Things to verify".
; Every controller returns one byte: bit0 ACCEL, bit1 BRAKE, bit2 LEFT, bit3 RIGHT,
; bit4 START, bit5 DOWN (brake/reverse), bit6 BOOST
ACC equ 0
BRK equ 1
LFT equ 2
RGT equ 3
STA equ 4
DWN equ 5
BST equ 6


cur_in:     db 0                                    ; input of the human car being updated

input_init:
    ; NextReg $05: joy1 mode = bits 7:6 + bit 3, joy2 mode = bits 5:4 + bit 1 (101 = MD1, 110 = MD2)
    ; UNVERIFIED from memory - see README.
    ld bc,PORT_NEXTREG_SEL : ld a,REG_JOY_MODE : out (c),a
    inc b : in a,(c) : and %00000101 : or %01101010 : out (c),a
    ret

; Read joystick port in C -> A = packed state
read_pad:
    in a,(c)
    ld d,a
    ld e,0
    bit PAD_B,d : jr z,.nb1
    set ACC,e
.nb1: bit PAD_A,d : jr z,.nb2
    set ACC,e
.nb2: bit PAD_C,d : jr z,.nb3
    set BRK,e
.nb3: bit PAD_L,d : jr z,.nb4
    set LFT,e
.nb4: bit PAD_R,d : jr z,.nb4b
    set RGT,e
.nb4b: bit PAD_D,d : jr z,.nb5
    set DWN,e
.nb5: bit PAD_U,d : jr z,.nb5u
    set BST,e
.nb5u: bit PAD_ST,d : jr z,.nb6
    set STA,e
.nb6: ld a,e
    ret


; keyboard-type controllers: five (port high byte, bit mask) pairs: up, down, left, right, fire
kbd_tab:
        db $F7,8, $F7,4, $F7,1, $F7,2, $F7,16       ; 2 INT2 L : keys 1-5 (left 1, right 2, down 3, up 4, fire 5)
        db $EF,2, $EF,4, $EF,16, $EF,8, $EF,1       ; 3 INT2 R : keys 6-0 (left 6, right 7, down 8, up 9, fire 0)
        db $EF,8, $EF,16, $F7,16, $EF,4, $EF,1      ; 4 CURSOR : 7 up, 6 down, 5 left, 8 right, 0 fire
        db $FB,1, $FD,1, $DF,2, $DF,1, $7F,1        ; 5 KEYS   : Q A O P SPACE
rk_mask: db 1,32,4,8,64                              ; ACC (up), DWN (down), LFT, RGT, BST (fire)
rk_res: db 0
rk_n:   db 0

read_kbd:                                           ; A = scheme 2..q5 -> A = controller byte
        sub 2 : ld l,a : ld h,0 : add hl,hl : ld d,h : ld e,l : add hl,hl : add hl,hl : add hl,de   ; *10
        ld de,kbd_tab : add hl,de
        xor a : ld (rk_res),a
        ld de,rk_mask : ld a,5 : ld (rk_n),a
.l:     ld b,(hl) : inc hl : ld c,$FE : in a,(c) : and (hl) : inc hl
        jr nz,.np                                   ; key not pressed (line still high)
        ld a,b : cp $7F : jr nz,.pr                  ; SPACE is half of BREAK (Caps Shift + Space) and of Symbol Shift + Space: with a shift down it is not the boost key
        ld bc,$FEFE : in a,(c) : rra : jr nc,.np
        ld b,$7F : in a,(c) : bit 1,a : jr z,.np
.pr:        ld a,(de) : ld c,a : ld a,(rk_res) : or c : ld (rk_res),a
.np:    inc de : ld a,(rk_n) : dec a : ld (rk_n),a : jr nz,.l
        ld a,(rk_res)
        ret

read_dev:                                           ; A = control choice 0..q5 -> A = controller byte
        cp 2 : jr nc,read_kbd
        ld bc,PORT_KEMP1 : or a : jr z,.p
        ld bc,PORT_KEMP2
.p:     jp read_pad

; menu: every device at once.  up=ACC down=DWN left=LFT right=RGT select=BST
menu_in:
        ld e,0
        ld a,2 : call .k
        ld a,3 : call .k
        ld a,4 : call .k
        ld a,5 : call .k
        ld bc,PORT_KEMP1 : call .p
        ld bc,PORT_KEMP2 : call .p
        ld bc,$BFFE : in a,(c) : bit 0,a : jr nz,.n
        set BST,e
.n:     ld a,e : ret
.k:     push de : call read_kbd : pop de : or e : ld e,a : ret
.p:     in a,(c) : ld d,a
        bit PAD_U,d : jr z,.q1
        set ACC,e
.q1:     bit PAD_D,d : jr z,.q2
        set DWN,e
.q2:     bit PAD_L,d : jr z,.q3
        set LFT,e
.q3:     bit PAD_R,d : jr z,.q4
        set RGT,e
.q4:     bit PAD_B,d : jr z,.q5
        set BST,e
.q5:     bit PAD_A,d : jr z,.q6
        set BST,e
.q6:     bit PAD_ST,d : ret z
        set BST,e
        ret

start_in:                                           ; A = STA when ENTER or a pad START is held (leaves the race)
        ld e,0
        ld bc,PORT_KEMP1 : in a,(c) : bit PAD_ST,a : jr z,.q1
        set STA,e
.q1:     ld bc,PORT_KEMP2 : in a,(c) : bit PAD_ST,a : jr z,.q2
        set STA,e
.q2:     ld bc,$BFFE : in a,(c) : bit 0,a : jr nz,.q3
        set STA,e
.q3:     ld a,e : ret
