.setcpu "65816"

.include "./ram/global.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import drawText
.import sendBytesToModem

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
  lda frameCounter
  and #$0001
  beq @skipDraw

  jsr readControllersInput

  sep #$20
  .a8
  lda controller2Input + 2
  bit #$80 ; check RX data transmitted
  beq @skipDraw
  lda #$00 ; null terminator
  pha
  lda controller2Input + 3
  pha
  rep #$20
  .a16
  jsr drawText
  sep #$20
  .a8
  pla
  pla
  rep #$20
  .a16
  @skipDraw:

; jsr drawControllerInput

  ; send AT command to modem
  lda frameCounter
  cmp #$0200
  bne :+
  pea $0000
  pea $0a0d
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla

  ; send ATZ command to modem
: lda frameCounter
  cmp #$0240
  bne :+
  pea $000a
  pea $0d5a
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla

  ; send AT&F command to modem
: lda frameCounter
  cmp #$0280
  bne :+
  pea $0000
  pea $0a0d
  pea $4626
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla

  ; send ATS7=60 command to modem
: lda frameCounter
  cmp #$02c0
  bne :+
  pea $000a
  pea $0d30
  pea $363d
  pea $3753
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla

  ; send ATS8=3 command to modem
: lda frameCounter
  cmp #$0300
  bne :+
  pea $0000
  pea $0a0d
  pea $333d
  pea $3853
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla

  ; send ATT command to modem
: lda frameCounter
  cmp #$0340
  bne :+
  pea $000a
  pea $0d54
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla

  ; send ATL0 command to modem
: lda frameCounter
  cmp #$0380
  bne :+
  pea $0000
  pea $0a0d
  pea $304c
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla

  ; send AT%B2400 command to modem
: lda frameCounter
  cmp #$03c0
  bne :+
  pea $0000
  pea $0a0d
  pea $3030
  pea $3432
  pea $4225
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla
  pla

  ; send ATS6=4 command to modem
: lda frameCounter
  cmp #$0400
  bne :+
  pea $0000
  pea $0a0d
  pea $343d
  pea $3653
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla

  ; send ATS9=6 command to modem
: lda frameCounter
  cmp #$0440
  bne :+
  pea $0000
  pea $0a0d
  pea $363d
  pea $3953
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla

  ; send ATS10=14 command to modem
: lda frameCounter
  cmp #$04c0
  bne :+
  pea $0000
  pea $0a0d
  pea $3431
  pea $3d30
  pea $3153
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla
  pla

  ; send ATS11=95 command to modem
: lda frameCounter
  cmp #$0500
  bne :+
  pea $0000
  pea $0a0d
  pea $3539
  pea $3d31
  pea $3153
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla
  pla

  ; send ATS91=15 command to modem
: lda frameCounter
  cmp #$0540
  bne :+
  pea $0000
  pea $0a0d
  pea $3531
  pea $3d31
  pea $3953
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla
  pla

  ; send ATX4 command to modem
: lda frameCounter
  cmp #$0580
  bne :+
  pea $0000
  pea $0a0d
  pea $3458
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla

  ; send ATD... command to modem
: lda frameCounter
  cmp #$05c0
  bne :+
  pea $0000
  pea $0a0d
  pea $3631
  pea $3330
  pea $3231
  pea $3032
  pea $3037
  pea $3044
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
  pla
  pla
  pla
  pla
  pla
:

  rti
.endproc
