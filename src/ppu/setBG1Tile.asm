.include "../registers.inc"
.include "../common/utility.asm"

.segment "ASSETS"

Tilemap:
  .incbin "../../assets/tilemap.bin"

.segment "STARTUP"

.export setBG1Tile
.proc setBG1Tile
  pha
  phb
  phd
  phx
  phy
  php

  rep #$30
  .a16
  .i16

  setDP $2100

  lda #$7800 ; BG1 tilemap base address
  sta .lobyte(VMADDL)

  sep #$20
  .a8

  lda #$01
  sta DMAP0
  lda #.lobyte(VMDATAL)
  sta BBAD0
  lda #.lobyte(Tilemap)
  sta A1T0L
  lda #.hibyte(Tilemap)
  sta A1T0H
  lda #.bankbyte(Tilemap)
  sta A1B0
  lda #$ff
  sta DAS0L
  lda #$0f
  sta DAS0H

  lda #$01
  sta MDMAEN

  plp
  ply
  plx
  pld
  plb
  pla

  rts
.endproc
