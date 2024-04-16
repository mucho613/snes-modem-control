; Clear BG1 Tile(#$0000 - #$4000) with 0. Expected to be called just after booting.
.macro clearBG1Tile
  .a16
  .i16

  lda #$0000
  sta rVRamAddress

  ldy #$8000

  lda #$0000

@loop:
  sta rVRamDataWrite
  dey
  bne @loop
.endmacro
