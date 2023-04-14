; BG1 の TileMap(#$4000 - #$4400)を 16×16 フォント表示用の配列に並び替える
.macro fontDisplayTileMap
  pea $0000 ; DB レジスタセット
  plb
  plb

  ldx #$4000
  stx rVRamAddress

  ldy #$0100

  lda #$0000
loop:
  sta rVRamDataWrite
  inc a

  sta rVRamDataWrite
  inc a

  pha
  txa
  clc
  adc #$0020 ; 16×16 の下半分の描画に移る
  tax
  pla

  stx rVRamAddress

  sta rVRamDataWrite
  inc a

  sta rVRamDataWrite
  inc a

  pha
  txa
  sec
  sbc #$001e

  bit #$001f ; 32 で割り切れる(1行描画が終了している)場合は、スキップ
  bne skip
  clc
  adc #$0020 ; 1行分下に移動させる
skip:

  tax
  pla

  stx rVRamAddress ; 演算終了した X レジスタの内容をセット

  dey

  bne loop
.endmacro
