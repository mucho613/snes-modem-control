.include "../registers.inc"

.segment "STARTUP"

.export initializeModem
.proc initializeModem
  .a16
  .i16

  pea $8000
  plb
  plb

  sep #$30
  .a8
  .i8

  ; latch
  lda #$01
  stz JOYOUT
  sta JOYOUT
  stz JOYOUT

  ldx #$10

  @loop1:
    lda JOYSER1

    dex
    bne @loop1

  ; latch
  lda #$01
  stz JOYOUT
  sta JOYOUT
  stz JOYOUT

  lda #$80
  sta WRIO
  lda JOYSER1

  ; R -> 0101 0010
  lda #$52
  pha
  ldx #$08
  @loop2:
    pla
    rol ; shift bit into carry
    pha ; save for later
    lda #$00
    ror
    sta WRIO ; Write to joypad serial data port 2
    lda JOYSER1

    dex
    bne @loop2

  pla

  ; Pulse latch
  lda #$01
  stz JOYOUT
  sta JOYOUT
  stz JOYOUT

  rep #$30
  .a16
  .i16

  rts
.endproc
