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
  ; 0xff のときはスクロール位置を 0 に戻す
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

  ; Update scroll line number
  lda terminalDownwardScroll
  asl
  sta WRDIVL
  stz WRDIVH
  lda #11 ; 文字の高さは 11 px
  sta WRDIVB
  NOP
  NOP
  NOP
  NOP
  NOP
  NOP
  NOP
  NOP
  lda RDDIVL
  sta terminalScrollLineNumber

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

  jsr updateHdmaTable
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
