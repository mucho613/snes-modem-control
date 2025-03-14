.macpack generic

.include "./common/utility.asm"
.include "./registers.inc"

.segment "STARTUP"

.import terminalDownwardScroll
.import terminalScrollLineNumber
.import evenFrameHdmaTable
.import oddFrameHdmaTable
.import bg1YScrollPos
.import frameCounter
.import updateHdmaTable
.import enableHdma
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

  jsr enableHdma

  ; Window settings
  lda bufW12SEL
  sta W12SEL

  lda bufWH0
  sta WH0

  lda bufWH1
  sta WH1

  lda #$01
  sta TMW

  lda #$01
  sta TSW

  plp
  ply
  plx
  pld
  plb
  pla

  rti
.endproc
