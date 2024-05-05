.include "./common/utility.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
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

testMessage: .byte "Hello!", $00

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

  inc32 frameCounter

  jsr execModemSettings

  jsr readControllersInput

  sep #$20
  .a8
  lda controller2InputData1
  bit #$80 ; RX data transmitted?
  beq @skipDraw
  lda controller2InputData1 + 1
  sta terminalTextBuffer
  pea terminalTextBuffer
  rep #$20
  .a16
  jsr print
  sep #$20
  .a8
  pla
  pla

  @skipDraw:

  rep #$20
  .a16

  rti
.endproc
