.include "../registers.inc"
.include "../common/utility.asm"
.include "nop.inc"

.code

.import copyNameTable
.import controller1Input
.import controller1InputPrev
.import controller2InputData1
.import controller2InputData2
.import terminalTextWriteBuffer
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
  beq @skipTransmitStartBitOn
  stz WRIO
  @skipTransmitStartBitOn:

  nop8Times
  nop8Times

  lda .lobyte(JOYSER1)
  lsr
  rol controller2InputData1
  lsr
  rol controller2InputData2

  ; Load transmit byte
  ; If transmitter buffer is empty, send 0x80
  lda modemTransmitBufferCount
  beq @transmitBufferEmpty
  lda modemTransmitBuffer, x
  bra @loadTransmitByteEnd
  @transmitBufferEmpty:
  lda #$80
  @loadTransmitByteEnd:

  ldy #$08

  @bitLoop:
    sta WRIO
    asl
    xba ; Write data -> B, Read data -> A

    nop8Times

    lda .lobyte(JOYSER1) ; Read controller 2 input
    lsr
    rol controller2InputData1
    rol controller2InputData1 + 1
    lsr
    rol controller2InputData2
    rol controller2InputData2 + 1

    xba ; Write data -> A, Read data -> B

    dey
    bne @bitLoop

  lda #$80
  sta WRIO ; WRIO bit on

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

