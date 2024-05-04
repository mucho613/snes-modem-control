.p816

.include "../ram/global.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem

.export execModemSettings
.proc execModemSettings
  .a16
  .i16

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
 :lda frameCounter
  cmp #$0280
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
  cmp #$0300
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
  cmp #$0380
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
  cmp #$0400
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
  cmp #$0480
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
  cmp #$0500
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
  cmp #$0580
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
  cmp #$0600
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
  cmp #$0680
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
  cmp #$0700
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
  cmp #$0780
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
  cmp #$0800
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
  cmp #$0880
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

:

.endproc
