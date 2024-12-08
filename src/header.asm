.import EmptyInt
.import Reset
.import VBlank

.segment "TITLE"
  .byte "Modem Control        " ; $FFC0: Game Title

.segment "HEADER"
  .byte $31                     ; $FFD5: ROM Type
  .byte $00                     ; $FFD6: Cartidge Type: ROM only
  .byte $06                     ; $FFD7: ROM Size: 17 ~ 32MBit
  .byte $00                     ; $FFD8: RAM Size: No RAM
  .byte $00                     ; $FFD9: Destination Code: Japan
  .byte $00                     ; $FFDA: Developer ID
  .byte $00                     ; $FFDB: ROM version
  .word $0000                   ; $FFDC: Checksum
  .word $ffff                   ; $FFDE: Checksum compliment

.segment "VECTORS"
  .word .loword(EmptyInt)       ; $FFE4: Native:COP
  .word .loword(EmptyInt)       ; $FFE6: Native:BRK
  .word .loword(EmptyInt)       ; $FFE8: Native:ABORT
  .word .loword(VBlank)         ; $FFEA: Native:NMI
  .word $0000                   ; None
  .word .loword(EmptyInt)       ; $FFEE: Native:IRQ

  .word $0000                   ; None
  .word $0000                   ; None

  .word .loword(EmptyInt)       ; $FFF4: Emulation:COP
  .word .loword(EmptyInt)       ; None
  .word .loword(EmptyInt)       ; $FFF8: Emulation:ABORT
  .word .loword(VBlank)         ; $FFFA: Emulation:NMI
  .word .loword(Reset)          ; $FFFC: Emulation:RESET
  .word .loword(EmptyInt)       ; $FFFE: Emulation:IRQ/BRK
