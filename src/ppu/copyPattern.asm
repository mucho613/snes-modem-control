.include "../registers.inc"
.include "../common/utility.asm"

.segment "STARTUP"

Font:
  .incbin "../../assets/font.bin"

.export copyPattern
.proc copyPattern
  .a16
  .i16

  pha
  phb

  setDP $2100

  stz .lobyte(VMADDL)
  setDBR .bankbyte(Font)

  ldx #$0000

  @loop:
    lda Font, x

    sta .lobyte(VMDATAL)

    inx
    inx
    cpx #$2000
    bne @loop

  plb
  pla

  rts
.endproc
