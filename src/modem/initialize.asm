.include "../registers.inc"
.include "../macro/utility.asm"
.include "constants.inc"
.include "nop.inc"

.code

.import frameCounter
.import modemLastDataReport, modemLastStatusReport, modemLastDiscardReason
.import modemResetStartFrame, modemReinitializeCount
.import modemSessionProbeSent, modemSessionRetryCount, modemSessionLineLength
.import modemResetQueues, modemSnapshotBegin, modemSnapshotEnd
.import modemRecordTrace, modemSetState

.export modemInitialize
.proc modemInitialize
  .a16
  .i16

  pha
  php
  sei
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

  ; JRA PAT drives controller-port-2 I/O low and then releases it at power-up.
  stz .lobyte(WRIO)
  lda #MODEM_TX_RELEASE
  sta .lobyte(WRIO)

  ; Capture one complete 16-bit report. Its data byte is deliberately not
  ; delivered to the RX ring; this read establishes status and identity only.
  stz modemLastDataReport
  stz modemLastDataReport + 1
  stz modemLastStatusReport
  stz modemLastStatusReport + 1

  stz .lobyte(JOYOUT)
  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)

  nop8Times
  nop8Times
  nop8Times

  ldx #$10
@readFullReport:
  lda .lobyte(JOYSER1)
  lsr
  rol modemLastDataReport
  rol modemLastDataReport + 1
  lsr
  rol modemLastStatusReport
  rol modemLastStatusReport + 1
  dex
  bne @readFullReport

  lda #MODEM_DISCARD_FULL_REPORT
  sta modemLastDiscardReason
  lda #MODEM_TRACE_POLL16
  jsr modemRecordTrace

  ; NDM24-specific R command. This is not an AT command and is kept in the
  ; transport initialization sequence until its exact semantics are known.
  stz .lobyte(JOYOUT)
  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)

  lda #MODEM_TX_RELEASE
  sta .lobyte(WRIO)
  lda .lobyte(JOYSER1)

  lda #MODEM_RESET_COMMAND
  ldy #$08
@writeResetCommand:
  asl
  xba
  lda #MODEM_TX_RELEASE
  bcs @writeResetBit
  lda #MODEM_TX_ASSERT
@writeResetBit:
  sta .lobyte(WRIO)
  nop8Times
  lda .lobyte(JOYSER1)
  xba
  dey
  bne @writeResetCommand

  lda #MODEM_TX_RELEASE
  sta .lobyte(WRIO)
  stz .lobyte(JOYOUT)
  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)

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
