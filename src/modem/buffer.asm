.include "constants.inc"
.include "../macro/utility.asm"

.code

.import modemDiagnosticMagic, modemDiagnosticVersion, modemDiagnosticSize
.import modemSnapshotSequence, modemDriverState, modemFlags
.import modemLastError, modemLastDiscardReason, modemPollTick, modemTraceFrozen
.import modemReceiveReadIndex, modemReceiveWriteIndex
.import modemTransmitReadIndex, modemTransmitWriteIndex
.import modemLastReceiveByte, modemLastTransmitByte
.import modemLastDataReport, modemLastStatusReport, modemTraceNextSequence
.import modemReceiveAcceptedCount, modemReceiveDiscardedCount
.import modemTransmitByteCount, modemReceiveOverflowCount
.import modemTransmitOverflowCount, modemPollLimitCount
.import modemAtStatus, modemAtExpectedResult
.import modemSessionLastResult, modemSessionLineLength, modemAtStartFrame
.import modemReceiveBuffer, modemTransmitBuffer
.import modemMailbox
.import terminalMirrorReceivedByte

.export modemInitializeDiagnostics
.export modemResetQueues
.export modemSnapshotBegin, modemSnapshotEnd
.export modemStoreReceivedByte, modemRecordDiscard
.export modemReadByte, modemQueueByte
.export modemPeekTransmitByte, modemConsumeTransmitByte
.export modemRecordPollLimit

.proc modemInitializeDiagnostics
  .a8
  .i8

  phb
  setDBR $7e

  lda #MODEM_DIAGNOSTIC_MAGIC_0
  sta modemDiagnosticMagic
  lda #MODEM_DIAGNOSTIC_MAGIC_1
  sta modemDiagnosticMagic + 1
  lda #MODEM_DIAGNOSTIC_MAGIC_2
  sta modemDiagnosticMagic + 2
  lda #MODEM_DIAGNOSTIC_MAGIC_3
  sta modemDiagnosticMagic + 3

  rep #$20
  .a16
  lda #MODEM_DIAGNOSTIC_VERSION
  sta modemDiagnosticVersion
  lda #MODEM_DIAGNOSTIC_SIZE
  sta modemDiagnosticSize
  sep #$20
  .a8

  lda #MODEM_STATE_OFF
  sta modemDriverState
  stz modemFlags
  stz modemLastError
  stz modemLastDiscardReason
  stz modemPollTick
  stz modemTraceFrozen
  stz modemReceiveReadIndex
  stz modemReceiveWriteIndex
  stz modemTransmitReadIndex
  stz modemTransmitWriteIndex
  stz modemLastReceiveByte
  stz modemLastTransmitByte
  stz modemLastDataReport
  stz modemLastDataReport + 1
  stz modemLastStatusReport
  stz modemLastStatusReport + 1
  stz modemTraceNextSequence
  stz modemTraceNextSequence + 1
  stz modemTraceNextSequence + 2
  stz modemTraceNextSequence + 3
  stz modemAtStatus
  stz modemAtExpectedResult
  stz modemSessionLastResult
  stz modemSessionLineLength
  stz modemAtStartFrame
  stz modemAtStartFrame + 1
  stz modemAtStartFrame + 2
  stz modemAtStartFrame + 3

  lda #MODEM_MAILBOX_MAGIC_0
  sta modemMailbox
  lda #MODEM_MAILBOX_MAGIC_1
  sta modemMailbox + 1
  lda #MODEM_MAILBOX_MAGIC_2
  sta modemMailbox + 2
  lda #MODEM_MAILBOX_MAGIC_3
  sta modemMailbox + 3

  rep #$20
  .a16
  lda #MODEM_MAILBOX_VERSION
  sta modemMailbox + 4
  lda #MODEM_MAILBOX_SIZE
  sta modemMailbox + 6
  sep #$20
  .a8

  plb
  rts
.endproc

; Clear queue ownership and transient errors without destroying cumulative
; counters or the trace leading up to an explicit reinitialization.
.proc modemResetQueues
  .a8
  .i8

  stz modemFlags
  stz modemLastError
  stz modemLastDiscardReason
  stz modemPollTick
  stz modemReceiveReadIndex
  stz modemReceiveWriteIndex
  stz modemTransmitReadIndex
  stz modemTransmitWriteIndex
  stz modemAtStatus
  stz modemAtExpectedResult
  stz modemSessionLastResult
  stz modemSessionLineLength
  rts
.endproc

.proc modemSnapshotBegin
  .a8
  pha
  modemIncrement32 modemSnapshotSequence
  pla
  rts
.endproc

.proc modemSnapshotEnd
  .a8
  pha
  modemIncrement32 modemSnapshotSequence
  pla
  rts
.endproc

; Internal RX producer. Input A is the candidate byte.
; Carry clear means stored; carry set means the 255-byte ring was full.
.proc modemStoreReceivedByte
  .a8
  .i8

  pha
  ldy modemReceiveWriteIndex
  iny
  tya
  cmp modemReceiveReadIndex
  beq overflow

  dey
  pla
  sta modemReceiveBuffer, y
  sta modemLastReceiveByte
  jsr terminalMirrorReceivedByte
  iny
  sty modemReceiveWriteIndex
  modemIncrement32 modemReceiveAcceptedCount
  clc
  rts

overflow:
  pla
  lda modemFlags
  ora #MODEM_FLAG_RX_OVERFLOW
  sta modemFlags
  lda #MODEM_DISCARD_RX_OVERFLOW
  sta modemLastDiscardReason
  modemIncrement32 modemReceiveOverflowCount
  modemIncrement32 modemReceiveDiscardedCount
  sec
  rts
.endproc

; Input A is a MODEM_DISCARD_* value.
.proc modemRecordDiscard
  .a8
  sta modemLastDiscardReason
  modemIncrement32 modemReceiveDiscardedCount
  rts
.endproc

; Public RX consumer. A contains the byte on success.
.proc modemReadByte
  .a8
  .i8

  phb
  phy
  setDBR $7e
  jsr modemSnapshotBegin

  ldy modemReceiveReadIndex
  cpy modemReceiveWriteIndex
  beq empty

  lda modemReceiveBuffer, y
  pha
  iny
  sty modemReceiveReadIndex
  jsr modemSnapshotEnd
  pla
  ply
  plb
  clc
  rts

empty:
  jsr modemSnapshotEnd
  ply
  plb
  sec
  rts
.endproc

; Public TX producer. Input A is the byte to queue.
.proc modemQueueByte
  .a8
  .i8

  phb
  phy
  setDBR $7e
  pha
  jsr modemSnapshotBegin

  ldy modemTransmitWriteIndex
  iny
  tya
  cmp modemTransmitReadIndex
  beq overflow

  dey
  pla
  sta modemTransmitBuffer, y
  iny
  sty modemTransmitWriteIndex
  jsr modemSnapshotEnd
  ply
  plb
  clc
  rts

overflow:
  pla
  lda modemFlags
  ora #MODEM_FLAG_TX_OVERFLOW
  sta modemFlags
  modemIncrement32 modemTransmitOverflowCount
  jsr modemSnapshotEnd
  ply
  plb
  sec
  rts
.endproc

; Internal TX consumer helpers. They assume DBR=$7e.
.proc modemPeekTransmitByte
  .a8
  .i8

  ldy modemTransmitReadIndex
  cpy modemTransmitWriteIndex
  beq empty
  lda modemTransmitBuffer, y
  clc
  rts

empty:
  sec
  rts
.endproc

.proc modemConsumeTransmitByte
  .a8
  .i8

  ldy modemTransmitReadIndex
  cpy modemTransmitWriteIndex
  beq done
  lda modemTransmitBuffer, y
  sta modemLastTransmitByte
  iny
  sty modemTransmitReadIndex
  modemIncrement32 modemTransmitByteCount

done:
  rts
.endproc

.proc modemRecordPollLimit
  .a8
  lda modemFlags
  ora #MODEM_FLAG_POLL_LIMIT
  sta modemFlags
  modemIncrement32 modemPollLimitCount
  rts
.endproc
