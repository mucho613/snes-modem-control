.p816

.segment "RODATA"

Palette:
  .incbin "../../assets/palette.bin"

.segment "STARTUP"

.export copyPalette
.proc copyPalette
  .a16
  .i16

  phb

  lda #$2100
  tcd

  sep #$20
  .a8

  stz $21 ; $2121: Address for CG-RAM Write

  lda #^Palette
  pha
  plb

  ldx #$0000

  @loop:
    lda Palette, x

    sta $22 ; $2122: Data for CG-RAM Write

    inx
    cpx #$0200
    bne @loop

  rep #$20
  .a16

  plb

  rts
.endproc
