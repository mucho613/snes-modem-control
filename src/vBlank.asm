.setcpu "65816"

.include "./ram/global.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import drawText
.import sendBytesToModem
.import sendBytesNToModem

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
  bit #$80 ; RX data transmitted?
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

  @skipDraw:

  rep #$20
  .a16

; jsr drawControllerInput

; jsr execModemSettings

  ; send ATL0 command to modem(Set speaker volume = low)
: lda frameCounter
  cmp #$0200
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

  ; send ATH1 command to modem(Off-hook)
: lda frameCounter
  cmp #$0240
  bne :+
  pea $0000
  pea $0a0d
  pea $3148
  pea $5441
  jsr sendBytesToModem
  pla
  pla
  pla
  pla
:

  rti
.endproc
