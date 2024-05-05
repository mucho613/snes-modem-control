.include "../modem/atCommand.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import frameCounter

.export execModemSettings
.proc execModemSettings
  .a16
  .i16

  ; send AT command to modem
  lda frameCounter
  cmp #$0200
  bne @skip
  pea at
  jsr sendBytesToModem
  pla
  @skip:

.endproc
