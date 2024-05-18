.include "../registers.inc"
.include "../common/utility.asm"
.include "nop.inc"

.segment "STARTUP"

.import copyNameTable
.import controller1Input
.import controller1InputPrev
.import controller2InputData1
.import controller2InputData2
.import terminalTextBuffer
.import modemReceiveBuffer
.import modemReceiveBufferCount
.import modemTransmitBuffer
.import modemTransmitBufferCount
.import print
.import pleaseConnectModemMessage

.export read9Bits
.proc read9Bits
  lda #$01
  sta .lobyte(JOYOUT) ; latch controller 1 & 2
  stz .lobyte(JOYOUT)

  lda modemTransmitBufferCount
  bne @skipTransmitStartBitOn
  lda #$80
  sta .lobyte(WRIO)
  @skipTransmitStartBitOn:

  nop8Times
  lda .lobyte(JOYSER1)
  lsr
  rol controller2InputData1
  lsr
  rol controller2InputData2

  ldy #$08

  @bitLoop:
    ldx #$00
    lda modemTransmitBuffer, x
    and #$7f

    sta .lobyte(WRIO)

    nop8Times

    ; 1 bit 左にシフトして保存しておく
    lda modemTransmitBuffer, x
    asl
    sta modemTransmitBuffer, x

    ; 読み取り
    lda .lobyte(JOYSER1)
    lsr
    rol controller2InputData1
    rol controller2InputData1 + 1
    lsr
    rol controller2InputData2
    rol controller2InputData2 + 1

    dey
    bne @bitLoop

  inx ; 次のバイトを指す

  ldy #$07
  @remainingBitsShiftLoop:
    clc
    rol controller2InputData1
    rol controller2InputData1 + 1
    clc
    rol controller2InputData2
    rol controller2InputData2 + 1
    dey
    bne @remainingBitsShiftLoop

  lda controller2InputData1
  bit #$80 ; RX data transmitted?
  beq @skipStoreToBuffer
  lda controller2InputData1 + 1
  ldy modemReceiveBufferCount
  sta modemReceiveBuffer, y
  inc modemReceiveBufferCount
  @skipStoreToBuffer:

  rts
.endproc

