.p816

.segment "RODATA"

Font:
  .incbin "../../assets/font.bin"

.segment "STARTUP"

.export copyPattern
.proc copyPattern
  .a16
  .i16

  phb

  lda #$2100
  tcd

  stz $16

  sep #$20
  .a8

  lda #^Font
  pha
  plb

  rep #$20
  .a16

  ldx #$0000

  @loop:
    lda Font, x

    sta $18 ; $2118

    inx
    inx
    cpx #$2000
    bne @loop

  plb

  rts
.endproc
