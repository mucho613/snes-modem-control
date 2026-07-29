.include "../registers.inc"
.include "../macro/utility.asm"
.include "constants.inc"
.include "nop.inc"

.code

.import frameCounter
.import modemDriverState, modemFlags, modemPollTick, modemBurstPending
.import modemPollStage
.import modemResetStartFrame
.import modemLastDataReport, modemLastStatusReport, modemLastDiscardReason
.import modemTransmitReadIndex, modemTransmitWriteIndex
.import modemSnapshotBegin, modemSnapshotEnd
.import modemStoreReceivedByte, modemRecordPollLimit
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
  lda #$10
  sta modemPollStage

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
  lda #$20
  sta modemPollStage
  jsr modemSnapshotBegin
  lda #$21
  sta modemPollStage
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
  lda #$22
  sta modemPollStage

@readCompleteReport:
  ; A complete 16-bit read reports status and identity. It can also consume
  ; the first pending RX byte. RX-present is authoritative for the current
  ; byte; Data2 remains only a hint for starting a transfer.
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
  lda #$23
  sta modemPollStage

  lda modemLastDataReport
  bit #MODEM_RX_PRESENT_MASK
  beq @fullReportHandled

  lda #MODEM_DISCARD_NONE
  sta modemLastDiscardReason
  lda modemLastDataReport + 1
  jsr modemStoreReceivedByte
  bcs @fullReportOverflow
  lda #MODEM_TRACE_RX_ACCEPTED
  jsr modemRecordTrace
  bra @fullReportHandled

@fullReportOverflow:
  lda #MODEM_TRACE_RX_DISCARDED
  jsr modemRecordTrace

@fullReportHandled:
  lda modemDriverState
  cmp #MODEM_STATE_RESETTING
  beq @pollEnd

  ldx #MODEM_POLL_BUDGET
@checkTransfer:
  lda #$24
  sta modemPollStage
  ; Once a burst has started, RX-present is the authoritative indication for
  ; the byte just returned. Keep clocking while valid bytes are arriving even
  ; if Data2 deasserts; Data2 can fall before the trailing LF is transferred.
  lda modemLastDiscardReason
  cmp #MODEM_DISCARD_NONE
  beq @transfer
  lda modemLastStatusReport + 1
  bit #MODEM_STATUS_TRANSFER_HINT_MASK
  bne @transfer
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  beq @pollEnd

@transfer:
  jsr modemTransfer9
  dex
  bne @checkTransfer

  lda modemLastDiscardReason
  cmp #MODEM_DISCARD_NONE
  beq @budgetReached
  lda modemLastStatusReport + 1
  bit #MODEM_STATUS_TRANSFER_HINT_MASK
  bne @budgetReached
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  beq @pollEnd

@budgetReached:
  lda #$01
  sta modemBurstPending
  jsr modemRecordPollLimit

@pollEnd:
  lda #$25
  sta modemPollStage
  lda #MODEM_TX_RELEASE
  sta .lobyte(WRIO)
  stz .lobyte(JOYOUT)
  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)
  jsr modemSnapshotEnd
  lda #$26
  sta modemPollStage

@return:
  lda #$30
  sta modemPollStage
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
