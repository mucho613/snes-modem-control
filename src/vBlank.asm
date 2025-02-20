.include "./common/utility.asm"
.include "./registers.inc"

.segment "STARTUP"

.import evenFrameHdmaTable
.import oddFrameHdmaTable
.import copyNameTable
.import communicateWithModem
.import modemReceiveBuffer
.import modemReceiveBufferCount
.import controller2InputData1
.import terminalTextWriteBuffer
.import drawFrameCount
.import drawControllerInput
.import execModemSettings
.import print
.import startup
.import sendBytesToModem
.import sendBytesNToModem
.import frameCounter

.export VBlank
.proc VBlank
  jml VBlankFast ; Jump to fast VBlank
.endproc

.proc VBlankFast
  pha
  phb
  phd
  phx
  phy
  php

  sep #$20
  .a8

  lda STAT78
  bit #%10000000
  beq @oddFrameHdma ; If odd frame, skip HDMA

  ; Even frame HDMA settings
  stz DMAP0
  lda #.lobyte(BG12NBA)
  sta BBAD0
  lda #.lobyte(evenFrameHdmaTable)
  sta A1T0L
  lda #.hibyte(evenFrameHdmaTable)
  sta A1T0H
  lda #.bankbyte(evenFrameHdmaTable)
  sta A1B0
  jmp @hdmaBranchEnd

  @oddFrameHdma:

  ; Even frame HDMA settings
  stz DMAP0
  lda #.lobyte(BG12NBA)
  sta BBAD0
  lda #.lobyte(oddFrameHdmaTable)
  sta A1T0L
  lda #.hibyte(oddFrameHdmaTable)
  sta A1T0H
  lda #.bankbyte(oddFrameHdmaTable)
  sta A1B0
  jmp @hdmaBranchEnd

  @hdmaBranchEnd:

  lda #$01
  sta HDMAEN ; Enable HDMA channel 1

  ; screll test ---
  ; sep #$20
  ; .a8

  ; lda frameCounter
  ; bit #$01
  ; bne @skip
  ; sta BG1VOFS
  ; lda frameCounter + 1
  ; sta BG1VOFS
  ; @skip:

  ; rep #$20
  ; .a16
  ; scroll test ---

  ; lda frameCounter
  ; bne @skip
  ; lda frameCounter + 2
  ; bne @skip
  ;   pea startup
  ;   jsr print
  ;   pla
  ; @skip:

  ; .scope drawTextFromModemReadBuffer
  ;   sep #$20
  ;   .a8
  ;   lda modemReceiveBufferCount
  ;   beq @skipDraw

  ;   rep #$20
  ;   .a16
  ;   pea modemReceiveBuffer
  ;   jsr print
  ;   pla
  ;   sep #$20
  ;   .a8

  ;   stz modemReceiveBufferCount

  ;   ldx #$0000
  ;   @clearBufferLoop:
  ;     stz modemReceiveBuffer, x
  ;     inx
  ;     cpx #$0040
  ;     bne @clearBufferLoop

  ;   @skipDraw:
  ;   rep #$20
  ;   .a16
  ; .endscope

  ; jsr execModemSettings

  ; jsr communicateWithModem

  sep #$20
  .a8

  lda #$00
  sta BG12NBA

  rep #$20
  .a16

  inc32 frameCounter

  plp
  ply
  plx
  pld
  plb
  pla

  rti
.endproc
