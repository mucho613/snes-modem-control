.segment "STARTUP"

.include "../../registers.inc"

.macpack generic

.import terminalScrollLineNumber
.import bg1TileHdmaEvenFrameTable
.import bg1TileHdmaOddFrameTable

; BG1 Tile の Base address を mid-frame で切り替えるための HDMA を有効化する
.export setBg1TileHdma
.proc setBg1TileHdma
  pha
  phb
  phd
  phx
  phy
  php

  sep #$20
  .a8
  rep #$10
  .i16

  stz DMAP0
  lda #.lobyte(BG12NBA)
  sta BBAD0

  lda STAT78
  bit #%10000000
  beq @oddFrameHdma

  @evenFrameHdma: ; Even frame HDMA settings
    rep #$20
    .a16
    lda terminalScrollLineNumber
    and #$00ff
    asl ; x2
    asl ; x4
    asl ; x8
    asl ; x16

    add #.loword(bg1TileHdmaEvenFrameTable)
    sta A1T0L
    sep #$20
    .a8
    lda #.bankbyte(bg1TileHdmaEvenFrameTable)
    sta A1B0
    jmp @hdmaBranchEnd

  @oddFrameHdma: ; Odd frame HDMA settings
    rep #$20
    .a16
    lda terminalScrollLineNumber
    and #$00ff
    asl ; x2
    asl ; x4
    asl ; x8
    asl ; x16

    add #.loword(bg1TileHdmaOddFrameTable)
    sta A1T0L
    sep #$20
    .a8
    lda #.bankbyte(bg1TileHdmaOddFrameTable)
    sta A1B0
    jmp @hdmaBranchEnd

  @hdmaBranchEnd:

  plp
  ply
  plx
  pld
  plb
  pla

  rts
.endproc
