.include "../registers.inc"

.import sendByteToModem

.segment "STARTUP"

.export sendBytesToModem
.proc sendBytesToModem
  .a16
  .i16

  pha
  phb
  phx
  phy

  pea $8000 ; change bank to $80
  plb
  plb

  sep #$20
  .a8

  tsx
  txy

  @bytesLoop:
    lda $000a, y

    beq @done ; if byte is $00, end transmission

    pha

    rep #$20
    .a16
    jsr sendByteToModem
    sep #$20
    .a8

    pla

    iny

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
