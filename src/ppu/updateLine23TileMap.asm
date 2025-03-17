.include "../registers.inc"
.include "../common/utility.asm"

.import terminalScrollLineNumber

.segment "STARTUP"

line0_22TileMap:
  .byte $00, $00, $02, $00, $04, $00, $06, $00, $08, $00, $0A, $00, $0C, $00, $0E, $00
  .byte $10, $00, $12, $00, $14, $00, $16, $00, $18, $00, $1A, $00, $1C, $00, $1E, $00
  .byte $20, $00, $22, $00, $24, $00, $26, $00, $28, $00, $2A, $00, $2C, $00, $2E, $00
  .byte $30, $00, $32, $00
line23TileMap:
  .byte $5C, $03, $4E, $03, $50, $03, $52, $03, $54, $03, $56, $03, $58, $03, $5A, $03
  .byte $5C, $03, $5E, $03, $60, $03, $62, $03, $64, $03, $66, $03, $68, $03, $6A, $03
  .byte $6C, $03, $6E, $03, $70, $03, $72, $03, $74, $03, $76, $03, $78, $03, $7A, $03
  .byte $7C, $03, $7E, $03

; スクロール量が 0～22 のときと、23 のときでは別のタイルマップ状態を適用する必要がある
; 文字の高さが 11 px のため、11 * 24 で 264 px の高さが必要
; 512 px の高さの BG1 内では、0～22 の表示では問題ないが、23 の表示時に最下部の 8 px 分が正しく表示されない
; そのため、23 のときはタイルマップを切り替える必要がある

.export updateLine23TileMap
.proc updateLine23TileMap
  pha
  php

  sep #$20
  .a8

  ; 23 行目のタイルマップを更新する
  ; 0～22 のときは、通常のタイルマップを使用
  ; 23 のときは、特別なタイルマップを使用
  lda terminalScrollLineNumber
  cmp #23
  beq @line23Update

  @line0_22Update:  ; 0 - 22 のタイルマップを使用
    rep #$30
    .a16
    .i16

    setDP $2100

    lda #$7803 ; BG1 tilemap base address
    sta .lobyte(VMADDL)

    sep #$20
    .a8

    lda #$01
    sta DMAP0
    lda #.lobyte(VMDATAL)
    sta BBAD0
    lda #.lobyte(line0_22TileMap)
    sta A1T0L
    lda #.hibyte(line0_22TileMap)
    sta A1T0H
    lda #.bankbyte(line0_22TileMap)
    sta A1B0
    lda #58
    sta DAS0L
    stz DAS0H

    lda #$01
    sta MDMAEN

    jmp @endUpdate

  @line23Update: ; 23 のタイルマップを更新する
    rep #$30
    .a16
    .i16

    setDP $2100

    lda #$7803 ; BG1 tilemap base address
    sta .lobyte(VMADDL)

    sep #$20
    .a8

    lda #$01
    sta DMAP0
    lda #.lobyte(VMDATAL)
    sta BBAD0
    lda #.lobyte(line23TileMap)
    sta A1T0L
    lda #.hibyte(line23TileMap)
    sta A1T0H
    lda #.bankbyte(line23TileMap)
    sta A1B0
    lda #58
    sta DAS0L
    stz DAS0H

    lda #$01
    sta MDMAEN

  @endUpdate:

  plp
  pla
  rts
.endproc
