.include "../registers.inc"
.include "../macro/utility.asm"
.include "constants.inc"

.code

.import frameCounter
.import nmitimenShadow
.import modemResetStartFrame, modemReinitializeCount
.import modemSessionProbeSent, modemSessionRetryCount, modemSessionLineLength
.import modemResetQueues, modemSnapshotBegin, modemSnapshotEnd
.import modemSetState

.export modemInitialize

; Send the NDM24-specific raw "R" initialization transaction. The waveform is
; intentionally kept instruction-for-instruction compatible with the original
; implementation that was verified by observing the NDM24 power lamp.
.proc modemSendRawInitialize
  .a16
  .i16

  phb
  pea $8000
  plb
  plb

  sep #$30
  .a8
  .i8

  lda #$01
  stz JOYOUT
  sta JOYOUT
  stz JOYOUT

  ldx #$10
@readReport:
  lda JOYSER1
  dex
  bne @readReport

  lda #$01
  stz JOYOUT
  sta JOYOUT
  stz JOYOUT

  lda #$80
  sta WRIO
  lda JOYSER1

  lda #$52
  pha
  ldx #$08
@writeR:
  pla
  rol
  pha
  lda #$00
  ror
  sta WRIO
  lda JOYSER1
  dex
  bne @writeR
  pla

  lda #$80
  sta WRIO

  lda #$01
  stz JOYOUT
  sta JOYOUT
  stz JOYOUT

  rep #$30
  .a16
  .i16
  plb
  rts
.endproc

.proc modemInitialize
  .a16
  .i16

  pha
  php
  sei ; Mask IRQ. NMI is gated explicitly around the raw waveform below.
  phb
  phd
  phx
  phy

  setDBR $7e
  setDP $4000

  sep #$30
  .a8
  .i8

  jsr modemSnapshotBegin
  jsr modemResetQueues
  stz modemSessionProbeSent
  stz modemSessionRetryCount
  stz modemSessionLineLength

  ; Use the hardware-verified raw "R" waveform verbatim.
  suspendNmi nmitimenShadow
  rep #$30
  .a16
  .i16
  jsr modemSendRawInitialize
  sep #$30
  .a8
  .i8
  restoreNmi nmitimenShadow

  rep #$20
  .a16
  lda frameCounter
  sta modemResetStartFrame
  lda frameCounter + 2
  sta modemResetStartFrame + 2
  sep #$20
  .a8

  modemIncrement32 modemReinitializeCount
  lda #MODEM_STATE_RESETTING
  jsr modemSetState
  jsr modemSnapshotEnd

  rep #$30
  .a16
  .i16

  ply
  plx
  pld
  plb
  plp
  pla
  rts
.endproc
