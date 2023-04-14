.setcpu "65816"

.segment "STARTUP"

.export VBlank
.proc VBlank
  pha
  phx
  php

  sep #$20
  .a8

  lda #$00
  pha
  plb

  lda #$01
  sta $4016

  lda #$80 ; 1st bit
  sta $4201

  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017

  ; AT<CR><LF>
  ; 41 54 0d 0a

  ; 0100 0001
  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$80
  sta $4201

  ; 2nd byte
  lda #$01
  sta $4016

  lda #$80 ; 1st bit
  sta $4201

  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017

  ; 0101 0100
  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  ; 3rd byte
  lda #$01
  sta $4016

  lda #$80 ; 1st bit
  sta $4201

  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017

  ; 0000 1101
  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$80
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$80
  sta $4201

  ; 4th byte
  lda #$01
  sta $4016

  lda #$80 ; 1st bit
  sta $4201

  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017
  lda $4017

  ; 0000 1010
  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  lda #$00
  sta $4201

  lda #$80
  sta $4201

  stp

  plp
  plx
  pla
  rti
.endproc
