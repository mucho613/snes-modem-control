.setcpu "65816"

.include "./ram/global.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawText

.export VBlank
.proc VBlank
  .a16
  .i16

  ; set bank to $7E
  sep #$20
  .a8
  lda #$7e
  pha
  plb
  rep #$20
  .a16

  ; increment the frame counter
  inc frameCounter
  bne @skip
  inc frameCounter + 2
  @skip:

  ; Fetch controller input
  jsr readControllersInput

  jsr drawFrameCount

  rti
.endproc
