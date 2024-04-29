.setcpu "65816"

.include "../ram/global.asm"

.segment "STARTUP"

.import copyNameTable

.export readControllersInput
.proc readControllersInput
  .a16
  .i16
  pha
  phb
  phx
  phy

  ; set bank to $7E
  sep #$20
  .a8
  lda #$7e
  pha
  plb
  rep #$20
  .a16

  ; copy inputs of previous frame
  lda controller1Input
  sta controller1InputPrev
  lda controller1Input + 2
  sta controller1InputPrev + 2

  lda controller2Input
  sta controller2InputPrev
  lda controller2Input + 2
  sta controller2InputPrev + 2

  ; read controller 1
  clc
  pea $4000
  pld

  lda #$01
  sta $16 ; latch controller 1 & 2
  stz $16

  ldx #$20

  sep #$20
  .a8

  @loop:
    lda $16
    lsr
    rol controller1Input
    rol controller1Input + 1
    rol controller1Input + 2
    rol controller1Input + 3

    lda $17
    lsr
    rol controller2Input
    rol controller2Input + 1
    rol controller2Input + 2
    rol controller2Input + 3

    dex
    bne @loop

  rep #$20
  .a16

  ply
  plx
  plb
  pla

  rts
.endproc
