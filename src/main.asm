.setcpu "65816"

.import initializeRegisters
.import transferText
.import copyPalette
.import copyPattern
.import copyText
.import VBlank
.import initializeModem

.include "./registers.inc"
.include "ppu/clearBG1Tile.asm"

.segment "RODATA"

.segment "STARTUP"
.proc Reset
  sei
  clc
  xce

  phk
  plb

  rep #$30
  .a16
  .i16

  jsr initializeRegisters

  ldx #$1fff ; Stack pointer value set
  txs

  clearBG1Tile
  jsr copyPalette ; Copy palette
  jsr copyPattern ; Copy pattern

  jsr copyText    ; Copy text

  sep #$30
  .a8
  .i8

  lda #$40
  sta $2107 ; BG 1 Address and Size

  lda #$01
  sta $212c ; Background and Object Enable (Main Screen)
  stz $212d ; Background and Object Disable (Sub Screen)

  lda #$0f
  sta $2100 ; Screen Display Register

  rep #$30
  .a16
  .i16

  jsr initializeModem

  sep #$30
  .a8
  .i8

  ; Enable NMI
  lda #$80
  sta $4200 ; NMI, V/H Count, and Joypad Enable

  cli

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
