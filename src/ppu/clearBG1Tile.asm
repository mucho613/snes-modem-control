.p816

.include "../registers.inc"

.segment "STARTUP"

; Clear BG1 Tile(#$0000 - #$4000) with 0. Expected to be called just after booting.
.export clearBG1Tile
.proc clearBG1Tile
  .a16
  .i16

  pha
  phb
  phy

  lda #$0000
  pha
  plb
  plb

  lda #$0000
  sta VMADDL

  ldy #$8000

  lda #$0000

@loop:
  sta VMDATAL
  dey
  bne @loop

  ply
  plb
  pla
.endproc
