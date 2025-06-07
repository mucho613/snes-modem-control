.macpack generic

.include "../registers.inc"
.include "../common/utility.asm"

.import terminalTextPointer

.code

; args:
; 0: string terminated with 0x00
.export print
.proc print
  .a16
  .i16

  pha
  phb
  phx
  phy

  lda #$2100
  tcd

  lda terminalTextPointer
  add #$4000 ; BG1 tilemap base address
  sta .lobyte(VMADDL) ; set text position

  ldx terminalTextPointer

  ; X is cursor position
  ; Y is pointer of text
  sep #$20
  .a8

  ldy #$0000

  @loop:
    lda ($0a, s), y ; a + b + x + y + return address

    cmp #$0d ; check for carriage return
    bne @checkLineFeed
    rep #$20
    .a16
    txa
    and #$ffe0 ; clear lower 5 bits
    tax

    clc
    adc #$4000
    sta .lobyte(VMADDL)
    sep #$20
    .a8
    bra @endCarriageReturn

    @checkLineFeed:
    cmp #$0a ; check for line feed
    bne @checkBackSpace
    rep #$20
    .a16
    txa
    and #$ffe0 ; clear lower 5 bits
    add #$20
    tax

    add #$4000
    sta .lobyte(VMADDL)
    sep #$20
    .a8
    bra @endLineFeed

    @checkBackSpace:
    cmp #$08 ; check for backspace
    bne @checkNullTerminator
    rep #$20
    .a16
    dex ; move back one character
    txa
    clc
    adc #$4000
    sta .lobyte(VMADDL)
    sep #$20
    .a8
    bra @endBackSpace

    @checkNullTerminator:
    cmp #$00 ; check for null terminator
    beq @transferEnd

    @transferNormalCharacter:
    sta .lobyte(VMDATAL) ; write character to VRAM
    stz .lobyte(VMDATAH)
    inx

    @endCarriageReturn:
    @endLineFeed:
    @endBackSpace:

    ; if text pointer reached end of BG1 tilemap, reset it
    cpx #$0800 ; X - $0800
    bne @noReset
    ldx #$4000 ; reset to base address
    stx .lobyte(VMADDL)
    ldx #$0000

    @noReset:
    iny
    cpy #$0080 ; up to 128 characters
    bne @loop

  @transferEnd:

  stx terminalTextPointer ; save text pointer position

  rep #$20
  .a16

  ; scrolling to follow new line
  txa
  and #$ffe0
  lsr
  lsr
  sub #$d9

  sep #$20
  .a8
  sta $0e ; write to scroll position register
  xba
  sta $0e
  rep #$20
  .a16

  ply
  plx
  plb
  pla

  rts
.endproc
