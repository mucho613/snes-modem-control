.setcpu "65816"

.segment "STARTUP"

.import copyNameTable

.export VBlank
.proc VBlank
  jsr copyNameTable

  rti
.endproc
