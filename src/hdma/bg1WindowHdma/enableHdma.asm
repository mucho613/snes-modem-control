.segment "STARTUP"

.include "../../registers.inc"

.macpack generic

.import bg1WindowHdmaTable

.export enableBg1WindowHdma
.proc enableBg1WindowHdma
  pha
  phb
  php

  sep #$20
  .a8

  lda #$01
  sta DMAP1
  lda #.lobyte(TM) ; TM と TS は連続して並んでいるので、HDMA Pattern 1 で 2バイトを同時に書き換える
  sta BBAD1

  lda #.lobyte(bg1WindowHdmaTable)
  sta A1T1L
  lda #.hibyte(bg1WindowHdmaTable)
  sta A1T1H
  lda #.bankbyte(bg1WindowHdmaTable)
  sta A1B1

  plp
  plb
  pla

  rts
.endproc
