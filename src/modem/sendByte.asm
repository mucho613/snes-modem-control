.setcpu "65816"

.segment "STARTUP"

.export sendByte
.proc sendByte
  sep #$30
  .a8
  .i8

  lda #$01 ; latch
  stz $4016
  sta $4016
  stz $4016

  ldx #$10

  @loop1:
    lda $4017

    dex
    bne @loop1

  ; Pulse latch
  lda #$01
  stz $4016
  sta $4016
  stz $4016

  ; R -> 0101 0010
  lda #$52
  pha
  ldx #$08

  @loop2:
    pla
    rol
    pha
    lda #$00
    ror

    pha
    lda $4017
    pla
    sta $4201 ; 0 or 1

    dex
    bne @loop2

  pla

  lda $4017
  lda #$80
  sta $4201 ; 1

  ; Pulse latch
  lda #$01
  stz $4016
  sta $4016
  stz $4016

  rep #$30
  .a16
  .i16

  rts
.endproc
