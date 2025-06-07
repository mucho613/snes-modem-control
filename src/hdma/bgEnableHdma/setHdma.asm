.code

.include "../../registers.inc"

.macpack generic

.import bgEnableHdmaTable

.export setBgEnableHdma
.proc setBgEnableHdma
  pha
  phb
  php

  sep #$20
  .a8

  lda #$01
  sta DMAP1
  lda #.lobyte(TM) ; TM と TS は連続して並んでいるので、HDMA Pattern 1 で 2バイトを同時に書き換える
  sta BBAD1

  lda #.lobyte(bgEnableHdmaTable)
  sta A1T1L
  lda #.hibyte(bgEnableHdmaTable)
  sta A1T1H
  lda #.bankbyte(bgEnableHdmaTable)
  sta A1B1

  plp
  plb
  pla

  rts
.endproc
