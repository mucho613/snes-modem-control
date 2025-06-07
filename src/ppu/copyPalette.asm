.include "../registers.inc"
.include "../common/utility.asm"

.code

Palette:
  .incbin "../../assets/palette.bin"

.export copyPalette
.proc copyPalette
  .a16
  .i16

  phb

  setDP $2100

  sep #$20
  .a8

  stz .lobyte(CGADD)

  setDBR .bankbyte(Palette)

  ldx #$0000

  @loop:
    lda Palette, x

    sta .lobyte(CGDATA)

    inx
    cpx #$0200
    bne @loop

  rep #$20
  .a16

  plb

  rts
.endproc
