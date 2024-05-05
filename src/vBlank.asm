.include "./common/utility.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
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
  pea startup
  jsr print
  pla
  @skip:

  inc32 frameCounter

  ; jsr readControllersInput

  ; jsr drawControllerInput

  jsr execModemSettings

  rti
.endproc
