.setcpu "65816"

.include "../registers.inc"

.segment "STARTUP"

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

  ; latch
  lda #$01
  stz JOYOUT
  sta JOYOUT
  stz JOYOUT

  ; 1st bit set
  stz WRIO
  lda JOYSER1

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
    lda JOYSER1

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
