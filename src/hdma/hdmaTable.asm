.segment "STARTUP"

.export evenFrameHdmaTable
evenFrameHdmaTable:
.byte 76
  .byte $00
.byte 128
  .byte $03
.byte 0

.export oddFrameHdmaTable
oddFrameHdmaTable:
.byte 75
  .byte $00
.byte 128
  .byte $03
.byte 0
