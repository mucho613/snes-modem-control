.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import frameCounter
.import executeModemSettings
.import dialing
.import modemTransmitBuffer
.import modemTransmitBufferCount
.import atl0
.import atd0123456789

.export execModemSettings
.proc execModemSettings
  .a16
  .i16

  pha
  phx

  .scope
    ; send ATL0 command to modem
    lda frameCounter
    cmp #$0200
    bne @skip
    lda frameCounter + 2
    bne @skip

    pea dialing
    jsr print
    pla

    sep #$30
    .a8
    .i8

    ldx #$00

    @copyLoop:
      lda atd0123456789, x
      sta modemTransmitBuffer, x
      beq @copyEnd
      inx
      bne @copyLoop

    @copyEnd:
    stx modemTransmitBufferCount

    rep #$30
    .a16
    .i16

    @skip:
  .endscope

  plx
  pla

  rts
.endproc
