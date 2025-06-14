.include "../registers.inc"
.include "../common/utility.asm"

.data
Font:
  .incbin "../../assets/pattern.bin"

.code

.export copyPattern
.proc copyPattern
  .a16
  .i16

  pha
  phb
  phx
  phy

  setDP $2100

  stz .lobyte(VMADDL)
  setDBR .bankbyte(Font)

  ldx #$0000
  @outerLoop:

    ldy #$0008
    @innerLoop1:
      lda Font, x

      sta .lobyte(VMDATAL)

      inx
      inx
      dey
      bne @innerLoop1

    ldy #$0008
    @innerLoop2:
      stz .lobyte(VMDATAL)

      dey
      bne @innerLoop2

    cpx #$6B40
    bne @outerLoop

  ply
  plx
  plb
  pla

  rts
.endproc
