.p816

.include "../registers.inc"
.include "../ram/global.asm"
.include "../common/utility.asm"

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

  setDBR $7e

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
  setDP $4000

  sep #$20
  .a8

  lda #$01
  sta .lobyte(JOYSER0) ; latch controller 1 & 2
  stz .lobyte(JOYSER0)

  ldx #$20

  @loop:
    lda .lobyte(JOYSER0)
    lsr
    rol controller1Input
    rol controller1Input + 1
    rol controller1Input + 2
    rol controller1Input + 3

    lda .lobyte(JOYSER1)
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
