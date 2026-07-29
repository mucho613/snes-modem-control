.macpack generic

.include "./macro/utility.asm"
.include "./registers.inc"

.code

.import terminalScrollLineNumber
.import bg1YScrollPos
.import updateLine23TileMap
.import frameCounter
.import setBg1TileHdma
.import setBgEnableHdma
.import scrollPositionTable
.import controllerPollTick, modemPollTick

.export VBlank
.proc VBlank
  jml VBlankFast
.endproc

.proc VBlankFast
  pha
  phb
  phd
  phx
  phy
  php

  rep #$20
  .a16
  inc32 frameCounter

  sep #$20
  .a8
  jsr updateLine23TileMap

  lda terminalScrollLineNumber
  asl
  tax
  lda scrollPositionTable, x
  sta bg1YScrollPos
  lda scrollPositionTable + 1, x
  sta bg1YScrollPos + 1

  lda bg1YScrollPos
  sta BG1VOFS
  lda bg1YScrollPos + 1
  sta BG1VOFS

  jsr setBg1TileHdma
  jsr setBgEnableHdma
  lda #%00000011
  sta HDMAEN

  ; Interrupt work ends here. Controller and NDM24 serial I/O are performed
  ; only by the main loop, so this interrupt cannot split a transfer.
  lda #$01
  sta controllerPollTick
  sta modemPollTick

  plp
  ply
  plx
  pld
  plb
  pla
  rti
.endproc
