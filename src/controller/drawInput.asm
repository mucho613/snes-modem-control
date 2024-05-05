.segment "STARTUP"

.import print
.import controller1Input
.import terminalTextBuffer

.macpack generic

.export drawControllerInput
.proc drawControllerInput
  .a16
  .i16

  sep #$20
  .a8

  ; 1st byte
  lda controller1Input
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  add #$37 ; A~F
  bra :++ ; transferEnd
: add #$30 ; 0~9
: sta terminalTextBuffer

  lda controller1Input
  lsr
  lsr
  lsr
  lsr
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  add #$37 ; A~F
  bra :++
: add #$30 ; 0~9
: sta terminalTextBuffer + 1

  ; 2nd byte
  lda controller1Input + 1
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  add #$37 ; A~F
  bra :++ ; transferEnd
: add #$30 ; 0~9
: sta terminalTextBuffer + 2

  lda controller1Input + 1
  lsr
  lsr
  lsr
  lsr
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  add #$37 ; A~F
  bra :++
: add #$30 ; 0~9
: sta terminalTextBuffer + 3

  ; 3nd byte
  lda controller1Input + 2
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  add #$37 ; A~F
  bra :++ ; transferEnd
: add #$30 ; 0~9
: sta terminalTextBuffer + 4

  lda controller1Input + 2
  lsr
  lsr
  lsr
  lsr
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  add #$37 ; A~F
  bra :++
: add #$30 ; 0~9
: sta terminalTextBuffer + 5

  ; 4th byte
  lda controller1Input + 3
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  add #$37 ; A~F
  bra :++ ; transferEnd
: add #$30 ; 0~9
: sta terminalTextBuffer + 6

  lda controller1Input + 3
  lsr
  lsr
  lsr
  lsr
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  add #$37 ; A~F
  bra :++
: add #$30 ; 0~9
: sta terminalTextBuffer + 7

  lda #$0a
  sta terminalTextBuffer + 8

  rep #$20
  .a16

  pea terminalTextBuffer
  jsr print
  pla
  rts
.endproc
