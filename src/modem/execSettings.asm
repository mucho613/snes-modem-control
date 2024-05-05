.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import frameCounter
.import executeModemSettings
.import at

.export execModemSettings
.proc execModemSettings
  .a16
  .i16

  ; send AT command to modem
  lda frameCounter
  cmp #$0100
  bne @skip
  lda frameCounter + 2
  bne @skip

  pea executeModemSettings
  jsr print
  pla

  pea at
  jsr sendBytesToModem
  pla
  @skip:

.endproc
