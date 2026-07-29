.code

.import print
.import controller1Input
.import modemLastDataReport
.import modemLastStatusReport
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

  setCharacterToBuffer modemLastDataReport, $00
  setCharacterToBuffer modemLastDataReport, $01
  setCharacterToBuffer modemLastStatusReport, $00
  setCharacterToBuffer modemLastStatusReport, $01

  lda #$0a
  sta terminalTextWriteBuffer + 8

  rep #$20
  .a16

  pea terminalTextWriteBuffer
  jsr print
  pla
  rts
.endproc
