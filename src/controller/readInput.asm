.include "../registers.inc"
.include "../common/utility.asm"

.segment "STARTUP"

.import copyNameTable
.import controller1Input
.import controller1InputPrev
.import controller2InputData1
.import controller2InputData2
.import terminalTextBuffer
.import modemReceiveBuffer
.import modemReceiveBufferCount
.import print
.import pleaseConnectModemMessage

.export readControllersInput
.proc readControllersInput
  .a16
  .i16

  pha
  phb
  phx
  phy

  setDP $4000

  @byteLoop:
    sep #$30
    .a8
    .i8

    lda #$01
    sta .lobyte(JOYOUT) ; latch controller 1 & 2
    stz .lobyte(JOYOUT)

    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    ldx #$10

    @bitLoop:
      lda .lobyte(JOYSER1)
      lsr
      rol controller2InputData1
      rol controller2InputData1 + 1
      lsr
      rol controller2InputData2
      rol controller2InputData2 + 1

      dex
      bne @bitLoop

    lda controller2InputData1
    bit #$80 ; RX data transmitted?
    beq @end
    lda controller2InputData1 + 1
    ldy modemReceiveBufferCount
    sta modemReceiveBuffer, y
    inc modemReceiveBufferCount
    @end:

    rep #$30
    .a16
    .i16

    pea terminalTextBuffer
    jsr print
    pla

    sep #$30
    .a8
    .i8

    ; lda controller2InputData2 + 1
    ; bit #$40
    ; bne @byteLoop

  lda #$01
  sta .lobyte(JOYOUT) ; latch controller 1 & 2
  stz .lobyte(JOYOUT)

  rep #$30
  .a16
  .i16

  ply
  plx
  plb
  pla

  rts
.endproc
