.segment "STARTUP"

.include "../registers.inc"

.macpack generic

.import terminalDownwardScroll
.import evenFrameHdmaTable
.import oddFrameHdmaTable

.export enableHdma
.proc enableHdma
  pha
  phb
  php

  sep #$20
  .a8

  lda STAT78
  bit #%10000000
  beq @oddFrameHdma ; If odd frame, skip HDMA

  ; Even frame HDMA settings
  stz DMAP0
  lda #.lobyte(BG12NBA)
  sta BBAD0
  lda #.lobyte(evenFrameHdmaTable)
  sta A1T0L
  lda #.hibyte(evenFrameHdmaTable)
  sta A1T0H
  lda #.bankbyte(evenFrameHdmaTable)
  sta A1B0
  jmp @hdmaBranchEnd

  @oddFrameHdma:

  ; Even frame HDMA settings
  stz DMAP0
  lda #.lobyte(BG12NBA)
  sta BBAD0
  lda #.lobyte(oddFrameHdmaTable)
  sta A1T0L
  lda #.hibyte(oddFrameHdmaTable)
  sta A1T0H
  lda #.bankbyte(oddFrameHdmaTable)
  sta A1B0
  jmp @hdmaBranchEnd

  @hdmaBranchEnd:

  lda #$01
  sta HDMAEN ; Enable HDMA channel 1

  plp
  plb
  pla
.endproc
