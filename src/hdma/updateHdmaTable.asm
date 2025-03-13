.segment "STARTUP"

.macpack generic

.import terminalDownwardScroll
.import evenFrameHdmaTable
.import oddFrameHdmaTable

.export updateHdmaTable
.proc updateHdmaTable
  pha
  phb
  php

  sep #$20
  .a8

  ; TODO
  ; - スクロール位置 4B のときにバグる

  ; スクロール量に応じて HDMA テーブルを分岐
  lda terminalDownwardScroll
  sub #76
  bpl @hdmaBranchPattern2

  lda #46
  sta evenFrameHdmaTable + 0
  dec ; odd frame で 1 行減らす（1行消えてしまうため）
  sta oddFrameHdmaTable + 0
  stz evenFrameHdmaTable + 1
  stz oddFrameHdmaTable + 1

  ; Update HDMA table
  ; BG1 のY座標に合わせて、BG1 tile の開始位置の更新走査線の番号を変える
  @hdmaBranchPattern1:
  ; 0 ～ 76 の範囲の場合
    lda #75
    sub terminalDownwardScroll
    sta evenFrameHdmaTable + 2
    sta oddFrameHdmaTable + 2
    stz evenFrameHdmaTable + 3
    stz oddFrameHdmaTable + 3

    lda #56
    sta evenFrameHdmaTable + 4
    sta oddFrameHdmaTable + 4
    lda #$03
    sta evenFrameHdmaTable + 5
    sta oddFrameHdmaTable + 5

    lda #1
    sta evenFrameHdmaTable + 6
    sta oddFrameHdmaTable + 6
    stz evenFrameHdmaTable + 7
    stz oddFrameHdmaTable + 7

    stz evenFrameHdmaTable + 8
    stz oddFrameHdmaTable + 8
    jmp @hdmaPatternBranchEnd

  ; 77 ～ 132 の範囲の場合
  @hdmaBranchPattern2:
    lda #133
    sub terminalDownwardScroll
    sta evenFrameHdmaTable + 2
    sta oddFrameHdmaTable + 2
    lda #$03
    sta evenFrameHdmaTable + 3
    sta oddFrameHdmaTable + 3

    lda #75
    sta evenFrameHdmaTable + 4
    inc
    sta oddFrameHdmaTable + 4
    stz evenFrameHdmaTable + 5
    stz oddFrameHdmaTable + 5

    lda #48
    sta evenFrameHdmaTable + 6
    sta oddFrameHdmaTable + 6
    lda #$03
    sta evenFrameHdmaTable + 7
    sta oddFrameHdmaTable + 7

    lda #1
    stz evenFrameHdmaTable + 8
    stz oddFrameHdmaTable + 8
    stz evenFrameHdmaTable + 9
    stz oddFrameHdmaTable + 9

    stz evenFrameHdmaTable + 10
    stz oddFrameHdmaTable + 10

  @hdmaPatternBranchEnd:

  plp
  plb
  pla

  rts
.endproc
