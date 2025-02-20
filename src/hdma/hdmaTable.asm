.segment "STARTUP"

.export evenFrameHdmaTable
evenFrameHdmaTable:
.byte 64
  .byte $00
.byte 64
  .byte $04
.byte 0

.export oddFrameHdmaTable
oddFrameHdmaTable:
.byte 63
  .byte $00
.byte 64
  .byte $04
.byte 0
