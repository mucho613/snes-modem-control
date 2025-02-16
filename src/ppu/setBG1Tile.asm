.include "../registers.inc"
.include "../common/utility.asm"

.segment "STARTUP"

vramResetByte: .byte $00

; Set BG1 Tile(#$0000 - #$4000).
.export setBG1Tile
.proc setBG1Tile
  .a16
  .i16

  pha
  phb

  setDP $2100

  lda #$7800 ; BG1 tilemap base address
  sta .lobyte(VMADDL)

  clc
  lda #$0000
  @loop1:
    sta .lobyte(VMDATAL)

    adc #$0002
    cmp #$0400
    bne @loop1

  clc
  lda #$0000
  @loop2:
    sta .lobyte(VMDATAL)

    adc #$0002
    cmp #$0400
    bne @loop2

  plb
  pla

  rts
.endproc
