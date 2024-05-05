.include "../registers.inc"
.include "../common/utility.asm"

.import sendByteToModem

.segment "STARTUP"

.export sendBytesNToModem
.proc sendBytesNToModem
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

  ldx $000a, y

  @bytesLoop:
    beq @done ; if x is zero

    lda $000b, y

    pha

    rep #$20
    .a16
    jsr sendByteToModem
    sep #$20
    .a8

    pla

    iny
    dex

    bne @bytesLoop

  @done:

  ; latch
  lda #$01
  stz JOYOUT
  sta JOYOUT
  stz JOYOUT

  rep #$20
  .a16

  ply
  plx
  plb
  pla

  rts
.endproc
