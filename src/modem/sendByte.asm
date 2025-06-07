.include "../registers.inc"
.include "../common/utility.asm"

.code

.export sendByteToModem
.proc sendByteToModem
  .a16
  .i16

  pha
  phb
  phx
  phy

  sep #$20
  .a8

  tsx
  txy

  setDP $4000

  ; latch
  lda #$01
  sta .lobyte(JOYOUT) ; latch controller 1 & 2
  stz .lobyte(JOYOUT)

  ; 1st bit set
  stz WRIO
  lda .lobyte(JOYSER1)

  ldx #$0008
  lda $000a, y
  pha
  @loop:
    pla
    rol ; shift bit into carry
    pha ; save for later
    lda #$00
    ror
    sta WRIO ; Write to joypad serial data port 2

    ; この NOP がないと WRIO で送ったバイトが取りこぼされる。
    ; 8個は確実に必要
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    lda .lobyte(JOYSER1)

    dex
    bne @loop

  pla

  rep #$20
  .a16

  ply
  plx
  plb
  pla

  rts
.endproc
