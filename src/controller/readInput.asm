.include "../registers.inc"
.include "../common/utility.asm"

.segment "STARTUP"

.import copyNameTable
.import controller1Input
.import controller1InputPrev
.import controller2InputData1
.import controller2InputData2
.import modemReceiveBuffer
.import modemReceiveBufferCount

.export readControllersInput
.proc readControllersInput
  .a16
  .i16

  pha
  phb
  phx
  phy

  ; copy inputs of previous frame
  ; lda controller1Input
  ; sta controller1InputPrev
  ; lda controller1Input + 2
  ; sta controller1InputPrev + 2

  setDP $4000

  sep #$30
  .a8
  .i8

  ldy #$00 ; counter

  @poll: ; Data1 の bit 2 が Low になるまでやる
    lda #$01
    sta .lobyte(JOYSER0) ; latch controller 1 & 2
    stz .lobyte(JOYSER0)

    ldx #$09

    @bitLoop:
      ; lda .lobyte(JOYSER0)
      ; lsr
      ; rol controller1Input
      ; rol controller1Input + 1
      ; rol controller1Input + 2
      ; rol controller1Input + 3

      lda .lobyte(JOYSER1)
      lsr
      rol controller2InputData1
      rol controller2InputData1 + 1
      lsr
      rol controller2InputData2
      rol controller2InputData2 + 1

      dex
      bne @bitLoop

    lda controller2InputData1 + 1
    bit #$01 ; Check Data1 - bit 9
    bne @notAvailableData
    sta modemReceiveBuffer, y
    @notAvailableData:

    iny

    tya ; up to 32 bytes
    cmp #$20
    beq @end

    lda controller2InputData2
    bit #$02 ; Check Data2 - bit 2
    beq @poll

  @end:

  sty modemReceiveBufferCount ; Save byte count

  lda #$01
  sta .lobyte(JOYSER0) ; latch controller 1 & 2
  stz .lobyte(JOYSER0)

  rep #$20
  .a16

  ply
  plx
  plb
  pla

  rts
.endproc
