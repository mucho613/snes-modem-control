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

  sep #$30
  .a8
  .i8

  .scope fetch16Bit1
    lda #$01
    sta .lobyte(JOYOUT) ; latch controller 1 & 2
    stz .lobyte(JOYOUT)

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

    lda #$01
    sta .lobyte(JOYOUT) ; latch controller 1 & 2
    stz .lobyte(JOYOUT)

    lda controller2InputData1
    bit #$80 ; RX data transmitted?
    beq @notPresented
    lda controller2InputData1 + 1
    sta terminalTextBuffer
    stz terminalTextBuffer + 1
    bra @end
    @notPresented:
    stz terminalTextBuffer
    @end:
  .endscope

  rep #$30
  .a16
  .i16

  pea terminalTextBuffer
  jsr print
  pla

  ply
  plx
  plb
  pla

  rts
.endproc
