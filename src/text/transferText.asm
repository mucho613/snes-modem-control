.setcpu "65816"

.import Text, transferCharacter

.segment "STARTUP"

.export transferText
.proc transferText
  .a16
  .i16

  ; テキストを描画する位置
  pea $0000

  ; UTF-16LE テキスト先頭からの offset 量(bytes)
  ldx #$0002 ; 先頭には BOM があるため 2 bytes ずらす

  @loop:
    sep #$20
    .a8

    lda #^Text
    pha
    plb

    rep #$20
    .a16

    lda Text, x

    beq @textTransferEnd ; 0x0000(NUL)だったときは終了

    cpa #$000a ; 改行(LF)かどうか
    bne @notLineFeed

    @lineFeed: ; LF の場合
      lda $01, s
      and #$fff0 ; 下位 4 bits だけをクリアして
      clc
      adc #$0010 ; 0x10 足す
      sta $01, s ; 次の行の先頭に描画位置を移動する
      jmp @characterTransferEnd

    @notLineFeed: ; LF でない場合
      pha ; Code point を Stack に積む
      jsr transferCharacter
      pla

      lda $01, s
      inc
      sta $01, s

  @characterTransferEnd:
    inx
    inx
    cpx #$0200 ; 0x0200 bytes(UTF-16 で 1 byte = 2 文字なので 256 文字)を上限とする
    bne @loop

  @textTransferEnd:

  pla
  rts
.endproc
