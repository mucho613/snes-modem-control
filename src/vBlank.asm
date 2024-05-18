.include "./common/utility.asm"

.segment "STARTUP"

.import copyNameTable
.import communicateWithModem
.import modemReceiveBuffer
.import modemReceiveBufferCount
.import controller2InputData1
.import terminalTextBuffer
.import drawFrameCount
.import drawControllerInput
.import execModemSettings
.import print
.import startup
.import sendBytesToModem
.import sendBytesNToModem
.import frameCounter

.export VBlank
.proc VBlank
  jml VBlankFast
.endproc

.proc VBlankFast
  .a16
  .i16

  lda frameCounter
  bne @skip
  lda frameCounter + 2
  bne @skip
    pea startup
    jsr print
    pla
  @skip:

  jsr execModemSettings

  ; jsr readControllersInput
  jsr communicateWithModem

  .scope drawTextFromModemReadBuffer
    sep #$20
    .a8
    lda modemReceiveBufferCount
    beq @skipDraw

    rep #$20
    .a16
    pea modemReceiveBuffer
    jsr print
    pla
    sep #$20
    .a8

    stz modemReceiveBufferCount

    @skipDraw:
    rep #$20
    .a16
  .endscope

  inc32 frameCounter

  rti
.endproc
