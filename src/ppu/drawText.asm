.setcpu "65816"

.include "../ram/global.asm"

.segment "STARTUP"

.export drawText
.proc drawText
  .a16
  .i16

  pha
  phb
  phx
  phy

  lda #$2100
  tcd

  phb ; save bank
  pea $7e00
  plb
  plb
  lda terminalTextPointer
  adc #$4000 ; BG1 tilemap base address
  sta $16 ; set text position
  plb ; restore bank

  tsx
  txy

  ldx terminalTextPointer

  sep #$20
  .a8

  @loop:
    lda $000a, y ; a + b + x + y + return address

    cmp #$0d ; check for carriage return
    bne @checkLineFeed
    rep #$20
    .a16
    txa
    and #$ffe0 ; clear lower 5 bits
    sta $16
    tax
    sep #$20
    .a8
    bra @endCarriageReturn

    @checkLineFeed:
    cmp #$0a ; check for line feed
    bne @checkNullTerminator
    rep #$20
    .a16
    txa
    and #$ffe0 ; clear lower 5 bits
    clc
    adc #$20
    sta $16
    tax
    sep #$20
    .a8
    bra @endLineFeed

    @checkNullTerminator:
    cmp #$00 ; check for null terminator
    beq @transferEnd

    @transferNormalCharacter:
    sta $18 ; write character to VRAM
    stz $19
    inx

    @endCarriageReturn:
    @endLineFeed:

    iny
    cpy #$0080
    bne @loop

  @transferEnd:

  stx terminalTextPointer ; save text pointer position

  rep #$20
  .a16

  ply
  plx
  plb
  pla

  rts
.endproc
