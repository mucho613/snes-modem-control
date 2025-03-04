.macpack generic

.include "./common/utility.asm"
.include "./registers.inc"

.segment "STARTUP"

.import terminalDownwardScroll
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

  ; スクロール位置が 0 ～ 131 の範囲で遷移するようにする
  ; 131 のときはスクロール位置を 0 に戻す
  @inputUp:
    lda terminalDownwardScroll
    dec
    cmp #$FF
    bne @upNegativeCheckEnd
    lda #131
    @upNegativeCheckEnd:
    sta terminalDownwardScroll

    jmp @inputBranchEnd

  ; 132 のときはスクロール位置を 0 に戻す
  @inputDown:
    lda terminalDownwardScroll
    inc
    cmp #132
    bne @downNegativeCheckEnd
    lda #$00
    @downNegativeCheckEnd:
    sta terminalDownwardScroll

    jmp @inputBranchEnd

  @inputBranchEnd:

  ; Update bg1YScrollPos
  rep #$20
  .a16
  lda terminalDownwardScroll
  and #$00FF
  asl
  sta bg1YScrollPos

  ; Update BG1VOFS
  sep #$20
  .a8
  lda bg1YScrollPos
  sta BG1VOFS
  lda bg1YScrollPos + 1
  sta BG1VOFS

  ; スクロール量に応じて HDMA テーブルを分岐
  lda terminalDownwardScroll
  sub #76
  bpl @hdmaBranchPattern2

  ; Update HDMA table
  ; BG1 のY座標に合わせて、BG1 tile の開始位置の更新走査線の番号を変える
  @hdmaBranchPattern1:
  ; 0 ～ 76 の範囲の場合
    lda #75
    sub terminalDownwardScroll
    sta evenFrameHdmaTable + 0
    ; dec ; odd frame で 1 行減らす（1行消えてしまうため）
    sta oddFrameHdmaTable + 0
    stz evenFrameHdmaTable + 1
    stz oddFrameHdmaTable + 1

    lda #56
    sta evenFrameHdmaTable + 2
    sta oddFrameHdmaTable + 2
    lda #$03
    sta evenFrameHdmaTable + 3
    sta oddFrameHdmaTable + 3

    lda #1
    sta evenFrameHdmaTable + 4
    sta oddFrameHdmaTable + 4
    stz evenFrameHdmaTable + 5
    stz oddFrameHdmaTable + 5

    stz evenFrameHdmaTable + 6
    stz oddFrameHdmaTable + 6
    jmp @hdmaPatternBranchEnd

  ; 77 ～ 132 の範囲の場合
  @hdmaBranchPattern2:
    lda #133
    sub terminalDownwardScroll
    sta evenFrameHdmaTable + 0
    ; dec ; odd frame で 1 行減らす（1行消えてしまうため）
    sta oddFrameHdmaTable + 0
    lda #$03
    sta evenFrameHdmaTable + 1
    sta oddFrameHdmaTable + 1

    lda #76
    sta evenFrameHdmaTable + 2
    sta oddFrameHdmaTable + 2
    stz evenFrameHdmaTable + 3
    stz oddFrameHdmaTable + 3

    lda #1
    sta evenFrameHdmaTable + 4
    sta oddFrameHdmaTable + 4
    lda #$03
    sta evenFrameHdmaTable + 5
    sta oddFrameHdmaTable + 5

    stz evenFrameHdmaTable + 6
    stz oddFrameHdmaTable + 6

  @hdmaPatternBranchEnd:

  plp
  ply
  plx
  pld
  plb
  pla

  rti
.endproc
