.include "./common/utility.asm"
.include "./modem/atCommand.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import sendBytesNToModem
.import frameCounter

.export VBlank
.proc VBlank
  jml VBlankFast
.endproc

.proc VBlankFast
  .a16
  .i16

  ; increment the frame counter
  inc32 frameCounter

  ; Fetch controller input
  jsr readControllersInput

  jsr drawControllerInput

; jsr execModemSettings

  pea at
  jsr print
  pla

  rti
.endproc
