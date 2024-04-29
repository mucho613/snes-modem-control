.setcpu "65816"

.include "./ram/global.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawText

.export VBlank
.proc VBlank
  .a16
  .i16

  ; set bank to $7E
  sep #$20
  .a8
  lda #$7e
  pha
  plb
  rep #$20
  .a16

  ; increment the frame counter
  inc frameCounter
  bne @skip
  inc frameCounter + 2
  @skip:

  ; Fetch controller input
  jsr readControllersInput

  ; lda frameCounter
  ; and #$003f
  ; bne @transferEnd
  ; pea $000d
  ; pea $3938
  ; pea $3736
  ; pea $3534
  ; pea $3332
  ; pea $3130
  ; jsr drawText
  ; pla
  ; pla
  ; pla
  ; pla
  ; pla
  ; pla
  ; @transferEnd:

  pea $000d

  sep #$20
  .a8

  ; 1st byte
  lda controller2Input
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++ ; transferEnd

: clc
  adc #$30 ; 0~9
: pha

  lda controller2Input
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
  lda controller2Input + 1
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++ ; transferEnd

: clc
  adc #$30 ; 0~9
: pha

  lda controller2Input + 1
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
  lda controller2Input + 2
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++ ; transferEnd

: clc
  adc #$30 ; 0~9
: pha

  lda controller2Input + 2
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
  lda controller2Input + 3
  and #$0f
  cmp #$0a ; 0~9: Negative、A~F: Positive
  bmi :+
  clc
  adc #$37 ; A~F
  bra :++ ; transferEnd

: clc
  adc #$30 ; 0~9
: pha

  lda controller2Input + 3
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
  jsr drawText
  pla ; 00 0d
  pla ; Bytes 0, 1
  pla ; Bytes 2, 3
  pla ; Bytes 4, 5
  pla ; Bytes 6, 7

  lda frameCounter


  rti
.endproc
