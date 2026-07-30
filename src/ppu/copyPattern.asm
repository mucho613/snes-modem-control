.include "../registers.inc"
.include "../macro/utility.asm"

.data
Font:
  .incbin "../../assets/font.bin"

.segment "BANK1_CODE"

.export copyPattern
.proc copyPattern
  .a16
  .i16

  pha
  phb
  phd
  phx

  setDP $2100
  stz .lobyte(VMADDL)
  setDBR .bankbyte(Font)

  ldx #$0000
@copy:
  lda Font, x
  sta .lobyte(VMDATAL)
  inx
  inx
  cpx #$1000
  bne @copy

  plx
  pld
  plb
  pla
  rtl
.endproc
