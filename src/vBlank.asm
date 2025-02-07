.include "./common/utility.asm"

.segment "STARTUP"

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
  .a16
  .i16

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

  inc32 frameCounter

  rti
.endproc
