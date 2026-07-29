.include "../registers.inc"
.include "../macro/utility.asm"
.include "constants.inc"
.include "nop.inc"

.code

.import frameCounter
.import modemDriverState, modemFlags, modemPollTick, modemBurstPending
.import modemResetStartFrame
.import modemLastDataReport, modemLastStatusReport, modemLastDiscardReason
.import modemTransmitReadIndex, modemTransmitWriteIndex
.import modemSnapshotBegin, modemSnapshotEnd
.import modemRecordDiscard, modemRecordPollLimit
.import modemTransfer9, modemRecordTrace, modemSetState

.export modemPoll
.proc modemPoll
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

  lda modemDriverState
  cmp #MODEM_STATE_OFF
  bne @checkErrorState
  jmp @return
@checkErrorState:
  cmp #MODEM_STATE_ERROR
  bne @checkWork
  jmp @return

@checkWork:
  lda modemPollTick
  bne @workAvailable
  lda modemBurstPending
  bne @workAvailable
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  bne @workAvailable
  jmp @return

@workAvailable:
  jsr modemSnapshotBegin
  stz modemPollTick
  stz modemBurstPending

  lda modemDriverState
  cmp #MODEM_STATE_RESETTING
  bne @readCompleteReport

  rep #$20
  .a16
  lda frameCounter
  sec
  sbc modemResetStartFrame
  cmp #MODEM_RESET_GUARD_FRAMES
  sep #$20
  .a8
  bcc @readCompleteReport

  lda #MODEM_STATE_PROBING
  jsr modemSetState

@readCompleteReport:
  ; A complete 16-bit read reports status and identity. JRA PAT does not
  ; deliver the embedded data byte to software.
  stz modemLastDataReport
  stz modemLastDataReport + 1
  stz modemLastStatusReport
  stz modemLastStatusReport + 1

  lda #MODEM_TX_RELEASE
  sta .lobyte(WRIO)
  stz .lobyte(JOYOUT)
  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)

  nop8Times
  nop8Times
  nop8Times

  ldx #$10
@read16:
  lda .lobyte(JOYSER1)
  lsr
  rol modemLastDataReport
  rol modemLastDataReport + 1
  lsr
  rol modemLastStatusReport
  rol modemLastStatusReport + 1
  dex
  bne @read16

  lda #MODEM_DISCARD_FULL_REPORT
  sta modemLastDiscardReason
  lda #MODEM_TRACE_POLL16
  jsr modemRecordTrace

  lda modemLastDataReport
  bit #MODEM_RX_PRESENT_MASK
  beq @fullReportHandled
  lda #MODEM_DISCARD_FULL_REPORT
  jsr modemRecordDiscard
  lda #MODEM_TRACE_RX_DISCARDED
  jsr modemRecordTrace

@fullReportHandled:
  lda modemDriverState
  cmp #MODEM_STATE_RESETTING
  beq @pollEnd

  ldx #MODEM_POLL_BUDGET
@checkTransfer:
  lda modemLastStatusReport + 1
  bit #MODEM_STATUS_READY_MASK
  bne @transfer
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  beq @pollEnd

@transfer:
  jsr modemTransfer9
  dex
  bne @checkTransfer

  lda modemLastStatusReport + 1
  bit #MODEM_STATUS_READY_MASK
  bne @budgetReached
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  beq @pollEnd

@budgetReached:
  lda #$01
  sta modemBurstPending
  jsr modemRecordPollLimit

@pollEnd:
  lda #MODEM_TX_RELEASE
  sta .lobyte(WRIO)
  stz .lobyte(JOYOUT)
  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)
  jsr modemSnapshotEnd

@return:
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
