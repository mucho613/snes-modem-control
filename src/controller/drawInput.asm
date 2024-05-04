.p816


.include "../ram/global.asm"

.segment "STARTUP"

.import print

.export drawControllerInput
.proc drawControllerInput
  .a16
  .i16

  pea $000a

  sep #$20
  .a8

  ; 1st byte
  lda controller1Input
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++ ; transferEnd

: clc
  adc #$30 ; 0~9
: pha

  lda controller1Input
  lsr
  lsr
  lsr
  lsr
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++
: clc
  adc #$30 ; 0~9
: pha

  ; 2nd byte
  lda controller1Input + 1
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++ ; transferEnd

: clc
  adc #$30 ; 0~9
: pha

  lda controller1Input + 1
  lsr
  lsr
  lsr
  lsr
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++
: clc
  adc #$30 ; 0~9
: pha


  ; 3nd byte
  lda controller1Input + 2
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++ ; transferEnd

: clc
  adc #$30 ; 0~9
: pha

  lda controller1Input + 2
  lsr
  lsr
  lsr
  lsr
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++
: clc
  adc #$30 ; 0~9
: pha

  ; 4th byte
  lda controller1Input + 3
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++ ; transferEnd

: clc
  adc #$30 ; 0~9
: pha

  lda controller1Input + 3
  lsr
  lsr
  lsr
  lsr
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++
: clc
  adc #$30 ; 0~9
: pha

  rep #$20
  .a16
  jsr print
  pla ; 00 0d
  pla ; Bytes 0, 1
  pla ; Bytes 2, 3
  pla ; Bytes 4, 5
  pla ; Bytes 6, 7

  rts
.endproc
