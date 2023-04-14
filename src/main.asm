.setcpu "65816"

.import initializeRegisters
.import transferText
.import textWritePosition
.import copyPalettes
.import VBlank

.include "./registers.inc"
.include "ppu/clearBG1Tile.asm"
.include "ppu/fontDisplayTileMap.asm"

.segment "RODATA"
.export FontHeader, FontBody, Text
FontHeader:
  .incbin "../assets/fontHeader.bin"
FontBody:
  .incbin "../assets/fontBody.bin"
Text:
  .incbin "../assets/test-utf-16le.txt"

.segment "STARTUP"
.proc Reset
  clc
  xce

  phk
  plb

  jsr initializeRegisters

  rep #$30
  .a16
  .i16

  clearBG1Tile ; BG1 のタイルマップをクリアする
  fontDisplayTileMap ; BG1 にフォントを並べて表示する

  ldx #$1fff ; Stack pointer value set
  txs

  jsr copyPalettes ; Palette のコピー

  jsr transferText ; テキストの転送

  sep #$20
  .a8

  lda #$00
  pha
  plb

  lda #$40
  sta $2107 ; BG 1 Address and Size

  lda #$01
  sta $212c ; Background and Object Enable (Main Screen)
  stz $212d ; Background and Object Enable (Sub Screen)

  lda #$0f
  sta $2100 ; Screen Display Register

  ; Enable NMI
  lda #$80
  sta $4200 ; NMI, V/H Count, and Joypad Enable

  rep #$20
  .a16

  rti
.endproc

.proc EmptyInt
  rti
.endproc

; カートリッジ情報
.segment "TITLE"
  .byte "Modem Control        " ; Game Title
.segment "HEADER"
  .byte $31                     ; ROM Type
  .byte $00                     ; Cartidge Type: ROM only
  .byte $0c                     ; ROM Size: 17 ~ 32MBit
  .byte $00                     ; RAM Size: No RAM
  .byte $00                     ; Destination Code: Japan
  .byte $33                     ; Fixed Value: 33H
  .byte $00                     ; Mask ROM Version
  .word $0000                   ; Complement Check
  .word $ffff                   ; Checksum
  .byte $ff, $ff, $ff, $ff      ; unknown

  .word .loword(EmptyInt)       ; Native:COP
  .word .loword(EmptyInt)       ; Native:BRK
  .word .loword(EmptyInt)       ; Native:ABORT
  .word .loword(VBlank)         ; Native:NMI
  .word $0000
  .word .loword(EmptyInt)       ; Native:IRQ

  .word $0000
  .word $0000

  .word .loword(EmptyInt)       ; Emulation:COP
  .word .loword(EmptyInt)
  .word .loword(EmptyInt)       ; Emulation:ABORT
  .word .loword(VBlank)         ; Emulation:NMI
  .word .loword(Reset)          ; Emulation:RESET
  .word .loword(EmptyInt)       ; Emulation:IRQ/BRK
