.include "../registers.inc"
.include "../macro/utility.asm"

.data

Palette:
  .incbin "../../assets/palette.bin"

.segment "BANK1_CODE"
.export copyPalette
.proc copyPalette
  .a16
  .i16

  phb

  setDP $2100

  m8
  stz .lobyte(CGADD)

  setDBR .bankbyte(Palette)

  ldx #$0000

  @loop:
    lda Palette, x

    sta .lobyte(CGDATA)

    inx
    cpx #$0200
    bne @loop

  m16
  plb

  rtl
.endproc
