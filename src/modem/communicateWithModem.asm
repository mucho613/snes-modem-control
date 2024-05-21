
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
.import read9Bits

.export communicateWithModem
.proc communicateWithModem
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

  ; 16 bits read
  lda #$01
  sta .lobyte(JOYOUT) ; latch controller 1 & 2
  stz .lobyte(JOYOUT)

  nop8Times
  nop8Times
  nop8Times

  ldx #$10

  @16bitLoop:
    lda .lobyte(JOYSER1)
    lsr
    rol controller2InputData1
    rol controller2InputData1 + 1
    lsr
    rol controller2InputData2
    rol controller2InputData2 + 1

    dex
    bne @16bitLoop

  ; FIXME: どうやら DATA1 2nd bit が最初に立つときにも有効なデータが DATA0 に入ってくるようなので、
  ; その byte も拾って Receive buffer に保存しなければならない

  ; エミュレータでの実行時に邪魔なので一旦コメントアウト
  ; ; ID がモデム(3)ではなかったらメッセージを出す
  ; lda controller2InputData1
  ; and #$0f
  ; cmp #$03
  ; beq @idCheckOk
  ; bra @communicateEnd
  ; @idCheckOk:

  ; 読み取るバイトがあれば即ループに入る。無ければ書き込むバイトのチェックに移る
  lda controller2InputData2 + 1
  bit #$40
  bne @execute9BitsRead

  ; 書き込むバイトが無ければ終了
  lda modemTransmitBufferCount
  beq @communicateEnd

  ldx #$00 ; Transfer byte pointer

  @execute9BitsRead:
  jsr read9Bits
  inx ; Increment transfer byte pointer

  lda controller2InputData2 + 1
  bit #$40
  bne @execute9BitsRead

  lda modemTransmitBufferCount
  beq @communicateEnd ; if 0, end communication
  dec
  sta modemTransmitBufferCount
  bne @execute9BitsRead

  @communicateEnd:

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
