.setcpu "65816"

.segment "RODATA"

Text:
  .incbin "../../assets/text.txt";

.segment "STARTUP"

.export copyNameTable
.proc copyNameTable
  phb

  .a16
  .i16

  lda #$2100
  tcd

	lda	#$4000
  sta $16

  sep #$20
  .a8

  lda #$7e
  pha
  plb

  ldx #$0000

  @loop:
    lda $2000, x

    sta $18
    stz $19
    inx
    cpx #$0080
    bne @loop

  rep #$20
  .a16

  plb

  rts
.endproc
