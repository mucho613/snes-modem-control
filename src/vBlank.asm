.macpack generic

.include "./common/utility.asm"
.include "./registers.inc"

.segment "STARTUP"

.import terminalScrollLineNumber
.import evenFrameHdmaTable
.import oddFrameHdmaTable
.import bg1YScrollPos
.import updateLine23TileMap
.import frameCounter
.import updateHdmaTable
.import enableBg1TileHdma
.import enableBg1WindowHdma
.import bufW12SEL
.import bufWH0
.import bufWH1
.import controller1Input
.import controller1InputPrev
.import controller1InputPulse
.import scrollPositionTable

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

  rep #$20
  .a16

  inc32 frameCounter

  sep #$20
  .a8

  ; Update BG1 tile map
  jsr updateLine23TileMap

  ; Update scroll position
  lda terminalScrollLineNumber
  asl
  tax
  lda scrollPositionTable, x
  sta bg1YScrollPos
  lda scrollPositionTable + 1, x
  sta bg1YScrollPos + 1

  ; Update BG1VOFS
  sep #$20
  .a8
  lda bg1YScrollPos
  sta BG1VOFS
  lda bg1YScrollPos + 1
  sta BG1VOFS

  ; HDMA settings
  jsr enableBg1TileHdma
  jsr enableBg1WindowHdma

  ; Enable HDMA
  lda #%00000011
  sta HDMAEN ; Enable HDMA channel 1 & 2

  ; Controller input
  lda controller1Input
  sta controller1InputPrev

  @joypadRead:
    lda HVBJOY
    and #$01
    bne @joypadRead

  lda JOY1H
  sta controller1Input
  eor controller1InputPrev
  and controller1Input
  sta controller1InputPulse

  bit #$08
  bne @inputUp
  bit #$04
  bne @inputDown
  jmp @inputBranchEnd

  ; スクロール行数を 0 ～ 23 の範囲で遷移するようにする
  ; 0xff のときは 23 に補正
  @inputUp:
    lda terminalScrollLineNumber
    dec
    cmp #$FF
    bne @upNegativeCheckEnd
    lda #23
    @upNegativeCheckEnd:
    sta terminalScrollLineNumber
    jmp @inputBranchEnd

  ; 24行目に達したら 0 に戻す
  @inputDown:
    lda terminalScrollLineNumber
    inc
    cmp #24
    bne @downNegativeCheckEnd
    lda #0
    @downNegativeCheckEnd:
    sta terminalScrollLineNumber
    jmp @inputBranchEnd
  @inputBranchEnd:

  plp
  ply
  plx
  pld
  plb
  pla

  rti
.endproc
