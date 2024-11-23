.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import frameCounter
.import startModemConfiguration
.import dialing
.import modemTransmitBuffer
.import modemTransmitBufferCount
.import att
.import atdNumber

.export execModemSettings
.proc execModemSettings
  .a16
  .i16

  pha
  phx

  .scope
    ; send ATL0 command to modem
    lda frameCounter
    cmp #$0180
    bne @skip
    lda frameCounter + 2
    bne @skip

    pea startModemConfiguration
    jsr print
    pla

    sep #$30
    .a8
    .i8

    ldx #$00

    @copyLoop:
      lda att, x
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

  .scope
    ; send dial command to modem
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
      lda atdNumber, x
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
