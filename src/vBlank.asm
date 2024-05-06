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

  jsr readControllersInput

  inc32 frameCounter

  rti
.endproc
