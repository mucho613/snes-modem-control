.include "./common/utility.asm"
.include "./registers.inc"

.segment "STARTUP"

.import evenFrameHdmaTable
.import oddFrameHdmaTable
.import bg1YScrollPos
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

  rep #$20
  .a16

  inc32 frameCounter

  sep #$20
  .a8

  @joypadRead:
  lda HVBJOY
  and #$01
  bne @joypadRead

  lda JOY1H

  bit #$08
  bne @inputUp
  bit #$04
  bne @inputDown
  jmp @inputBranchEnd

  @inputUp:
  rep #$20
  .a16
  lda bg1YScrollPos
  dec
  sta bg1YScrollPos
  jmp @inputBranchEnd

  @inputDown:
  rep #$20
  .a16
  lda bg1YScrollPos
  inc
  sta bg1YScrollPos
  jmp @inputBranchEnd

  @inputBranchEnd:

  ; Update BG1VOFS
  sep #$20
  .a8
  lda bg1YScrollPos
  sta BG1VOFS
  lda bg1YScrollPos + 1
  sta BG1VOFS

  ; Update HDMA table
  lda bg1YScrollPos
  eor #$FF
  clc
  adc #152
  lsr ; 76 lines
  sta evenFrameHdmaTable + 0
  lda #$00
  sta evenFrameHdmaTable + 1
  lda #128 ; 128 lines
  sta evenFrameHdmaTable + 2
  lda #$03
  sta evenFrameHdmaTable + 3
  lda #$00
  sta evenFrameHdmaTable + 4

  lda bg1YScrollPos
  eor #$FF
  clc
  adc #150
  lsr ; 75 lines
  sta oddFrameHdmaTable + 0
  lda #$00
  sta oddFrameHdmaTable + 1
  lda #128 ; 128 lines
  sta oddFrameHdmaTable + 2
  lda #$03
  sta oddFrameHdmaTable + 3
  lda #$00
  sta oddFrameHdmaTable + 4

  plp
  ply
  plx
  pld
  plb
  pla

  rti
.endproc
