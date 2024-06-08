.include "../registers.inc"
.include "../common/utility.asm"

.segment "STARTUP"

vramResetByte: .byte $00

; Clear BG1 Tile(#$0000 - #$4000) with 0. Expected to be called just after booting.
.export clearBG1Tile
.proc clearBG1Tile
  .a16
  .i16

  pha
  phb
  phy

  setDP $4300

  lda #$0000
  sta VMADDL

  stz .lobyte(DAS0L)

  lda #.loword(vramResetByte)
  sta .lobyte(A1T0L)

  sep #$20
  .a8

  lda #.bankbyte(vramResetByte)
  sta .lobyte(A1B0)

  lda #$09 ; A address fixed, VRAM transfer
  sta .lobyte(DMAP0) ; DMA parameters

  lda #.lobyte(VMDATAL)
  sta .lobyte(BBAD0)

  lda #$01
  sta MDMAEN

  rep #$20
  .a16

  ply
  plb
  pla

  rts
.endproc
