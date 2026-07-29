.code

.import modemLastDataReport
.import pleaseConnectModemMessage
.import print

.export idCheck
.proc idCheck
  .a8
  .i8

  pha

  lda modemLastDataReport
  and #$0f
  cmp #$03
  beq @ok

  pea pleaseConnectModemMessage
  jsr print
  pla
  pla
  @ok:

  pla

  rts
.endproc
