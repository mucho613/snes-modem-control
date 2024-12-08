.segment "STARTUP"

.import print
.import controller1Input
.import controller2InputData1
.import controller2InputData2
.import terminalTextWriteBuffer

.macpack generic

.macro setCharacterToBuffer address, offset
  .a8
  .i8

  .scope
    lda address + offset
    and #$0f
    cmp #$0a ; 0~9: Negative、A~F: Positive
    bmi @numericCharacter
    add #$37 ; A~F
    bra @setToBuffer
    @numericCharacter:
      add #$30 ; 0~9
    @setToBuffer:
      sta terminalTextWriteBuffer + (offset * 2) + 1
  .endscope

  .scope
    lda address + offset
    lsr
    lsr
    lsr
    lsr
    cmp #$0a ; 0~9: Negative、A~F: Positive
    bmi @numericCharacter
    add #$37 ; A~F
    bra @setToBuffer
    @numericCharacter:
      add #$30 ; 0~9
    @setToBuffer:
      sta terminalTextWriteBuffer + (offset * 2)
  .endscope
.endmacro

.export drawControllerInput
.proc drawControllerInput
  .a16
  .i16

  sep #$20
  .a8

  setCharacterToBuffer controller2InputData1, $00
  setCharacterToBuffer controller2InputData1, $01
  setCharacterToBuffer controller2InputData1, $02
  setCharacterToBuffer controller2InputData1, $03

  lda #$0a
  sta terminalTextWriteBuffer + 8

  rep #$20
  .a16

  pea terminalTextWriteBuffer
  jsr print
  pla
  rts
.endproc
