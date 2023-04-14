.setcpu "65816"

.segment "RODATA"

Palette:
  .incbin "../../assets/palette.bin"

.segment "STARTUP"

.export copyPalettes
.proc copyPalettes
  .a16
  .i16

  lda #$2121
  tcd

  sep #$20
  .a8

  stz $00 ; $2121: Address for CG-RAM Write

  lda #^Palette
  pha
  plb

  ldx #$0000

  @loop:
    lda Palette, x

    sta $01 ; $2122: Data for CG-RAM Write

    inx
    cpx #$0200
    bne @loop

  rep #$20
  .a16

  rts
.endproc
