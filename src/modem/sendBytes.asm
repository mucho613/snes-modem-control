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

  sep #$20
  .a8

  ldy #$0000

  @bytesLoop:
    lda ($0a, s), y

    beq @done ; if byte is $00, end transmission

    pha

    rep #$20
    .a16
    jsr sendByteToModem
    sep #$20
    .a8

    pla

    ; latch
    lda #$01
    stz JOYOUT
    sta JOYOUT
    stz JOYOUT

    iny

    bne @bytesLoop

  @done:

  rep #$20
  .a16

  ply
  plx
  plb
  pla

  rts
.endproc
