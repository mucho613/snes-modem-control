.include "../registers.inc"
.include "../common/utility.asm"

.import sendByteToModem
.import modemTransmitBuffer
.import modemTransmitBufferCount

.code

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

  lda modemTransmitBufferCount ; if no bytes to send, return
  beq @done

  ldy #$0000

  setDP $4000

  ; latch
  lda #$01
  sta .lobyte(JOYOUT) ; latch controller 1 & 2
  stz .lobyte(JOYOUT)

  @bytesLoop:
    lda modemTransmitBuffer, y

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
    sta .lobyte(JOYOUT) ; latch controller 1 & 2
    stz .lobyte(JOYOUT)

    iny

    bne @bytesLoop

  @done:

  stz modemTransmitBufferCount

  rep #$20
  .a16

  ply
  plx
  plb
  pla

  rts
.endproc
