.segment "STARTUP"

.import controller2InputData1
.import pleaseConnectModemMessage
.import print

.export idCheck
.proc idCheck
  .a16
  .i16

  pha

  lda controller2InputData1
  and #$000f
  cmp #$0003
  beq @ok

  pea pleaseConnectModemMessage
  jsr print
  pla
  @ok:

  pla

  rts
.endproc

