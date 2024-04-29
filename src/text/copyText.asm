.setcpu "65816"

.segment "RODATA"

Text:
  .incbin "../../assets/text.txt"

.segment "STARTUP"

.export copyText
.proc copyText
  .a16
  .i16

  phb

  lda #$2100
  tcd

  stz $16

  sep #$20
  .a8

  lda #^Text
  pha
  plb

  ldx #$0040

  @loop:
    lda Text, x

    sep #$10
    .i8

    phb ; save the bank
    ldy #$7e
    phy
    plb ; set the bank to $7e

    rep #$10
    .i16

    sta $2000, x

    plb ; restore the bank

    cmp #$00 ; check for null terminator
    beq @transferEnd

    cmp #$0d ; check for carriage return


    inx
    cpx #$0080
    bne @loop

  @transferEnd:

  plb

  rep #$20
  .a16

  rts
.endproc
