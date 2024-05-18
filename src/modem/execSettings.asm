.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import frameCounter
.import executeModemSettings
.import modemTransmitBuffer
.import modemTransmitBufferCount
.import atl0
.import ati3

.export execModemSettings
.proc execModemSettings
  .a16
  .i16

  pha
  phx

  .scope
    ; send AT command to modem
    lda frameCounter
    cmp #$0200
    bne @skip
    lda frameCounter + 2
    bne @skip

    pea executeModemSettings
    jsr print
    pla

    sep #$30
    .a8
    .i8

    ldx #$00

    @copyLoop:
      lda ati3, x
      sta modemTransmitBuffer, x
      beq @copyEnd
      inx
      bne @copyLoop

    @copyEnd:
    inx
    stx modemTransmitBufferCount

    @skip:

    rep #$30
    .a16
    .i16
  .endscope

  plx
  pla

  rts
.endproc
