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
.import ati4

.export execModemSettings
.proc execModemSettings
  .a16
  .i16

  ; send AT command to modem
  lda frameCounter
  cmp #$0200
  bne @skip1
  lda frameCounter + 2
  bne @skip1

  pea executeModemSettings
  jsr print
  pla

  pea at
  jsr sendBytesToModem
  pla
  @skip1:

  ; send AT command to modem
  lda frameCounter
  cmp #$0300
  bne @skip2
  lda frameCounter + 2
  bne @skip2

  pea executeModemSettings
  jsr print
  pla

  pea ati4
  jsr sendBytesToModem
  pla
  @skip2:

  rts
.endproc
