.p816

.include "./ram/global.asm"
.include "./common/utility.asm"

.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import sendBytesNToModem

.export VBlank
.proc VBlank
  jml VBlankFast
.endproc

.proc VBlankFast
  .a16
  .i16

  phb

  setDBR $7e

  ; increment the frame counter
  inc32 frameCounter

  ; Fetch controller input
  jsr readControllersInput

  jsr drawControllerInput

; jsr execModemSettings

  plb

  rti
.endproc
