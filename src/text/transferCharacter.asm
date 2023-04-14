.setcpu "65816"

.import FontHeader, FontBody, Text

.include "../registers.inc"

.define utf16Word $0100
.define characterDataBank $0102

.segment "STARTUP"

; BG1 の Tile(#$4000 - #$4400)上に、UTF-16 テキストの内容を並べる
.export transferCharacter
.proc transferCharacter
  .a16
  .i16

  pea $0000
  plb
  plb

  lda $03, s ; Code point を読み込む

  @calculateGlyphAddress:
  sta utf16Word
  stz characterDataBank

  asl utf16Word ; アドレスを 3 bits 左シフト
  rol characterDataBank
  asl utf16Word
  rol characterDataBank
  asl utf16Word
  rol characterDataBank

  clc
  lda #.LOWORD(FontHeader)
  adc utf16Word
  sta utf16Word

  lda #.HIWORD(FontHeader)
  adc characterDataBank
  sta characterDataBank

  lda #utf16Word
  tcd
  lda [$00] ; Glyph の Header を読み込む

  and #$0001 ; Glyph が存在するか
  bne @glyphExists

  @glyphNotExist: ; Glyph が存在しない場合
    lda #$3000 ; 全角スペース "　" のコードポイント

    pea $0000
    plb
    plb

    jmp @calculateGlyphAddress

  @glyphExists: ; Glyph が存在する場合
    ; Glyph が存在するので、Glyph の Index を取得する
    lda #$0002 ; Index がある位置にずらす offset 量を Y にセット
    tay
    lda [$00], y ; Glyph の Index を取得

    xba ; Glyph の Index 番号のデータが Big Endian なので、バイトの上位下位を反転

    sta utf16Word
    stz characterDataBank

    asl utf16Word ; アドレスを 5 bits 左シフト
    rol characterDataBank
    asl utf16Word
    rol characterDataBank
    asl utf16Word
    rol characterDataBank
    asl utf16Word
    rol characterDataBank
    asl utf16Word
    rol characterDataBank

    clc
    lda #.LOWORD(FontBody)
    adc utf16Word
    sta utf16Word

    lda #.HIWORD(FontBody)
    adc characterDataBank
    sta characterDataBank

    pea $0000
    plb
    plb

    ; ここからタイルの転送
    lda $05, s
    asl ; 5 bits 左シフトで VRAM Address に変換する
    asl
    asl
    asl
    asl
    sta rVRamAddress

    ldy #$0000

    lda #utf16Word
    tcd

    sep #$20
    .a8

    @loop:
      ; Direct Page レジスタが指し示す先に、Glyph データの先頭を指し示す 16 bit アドレスが入っている
      lda [$00], y
      sta rVRamDataWrite
      stz rVRamDataWrite + 1

      iny
      cpy #$0020
      bne @loop

  rep #$20
  .a16

  rts
.endproc
