.include "../modem/generated.inc"

.bss

.export frameCounter
frameCounter: .res $4

.export controller1Input, controller1InputPrev, controller1InputPulse
controller1Input: .res $2
controller1InputPrev: .res $2
controller1InputPulse: .res $2

.export controllerPollTick
controllerPollTick: .res $1

; Software mirror of the write-only NMITIMEN register. Low-level controller
; port waveforms save, clear, and restore this byte around bit-bang sections.
.export nmitimenShadow
nmitimenShadow: .res $1

; Public, versioned diagnostic ABI. Keep labels in the same order as
; spec/ndm24.toml and assert every externally visible offset below.
.export modemState, modemStateEnd
.export modemDiagnosticMagic, modemDiagnosticVersion, modemDiagnosticSize
.export modemSnapshotSequence, modemDriverState, modemFlags
.export modemLastError, modemLastDiscardReason, modemPollTick, modemTraceFrozen
.export modemReceiveReadIndex, modemReceiveWriteIndex
.export modemTransmitReadIndex, modemTransmitWriteIndex
.export modemLastReceiveByte, modemLastTransmitByte
.export modemLastDataReport, modemLastStatusReport, modemTraceNextSequence
.export modemReceiveAcceptedCount, modemReceiveDiscardedCount
.export modemTransmitByteCount, modemReceiveOverflowCount
.export modemTransmitOverflowCount, modemPollBudgetYieldCount, modemTimeoutCount
.export modemReinitializeCount, modemTraceOverwrittenCount, modemResetStartFrame
.export modemTerminalDroppedCount
.export modemAtStatus, modemAtExpectedResult
.export modemSessionLastResult, modemSessionLineLength, modemAtStartFrame

modemState:
modemDiagnosticMagic: .res $4
modemDiagnosticVersion: .res $2
modemDiagnosticSize: .res $2
modemSnapshotSequence: .res $4
modemDriverState: .res $1
modemFlags: .res $1
modemLastError: .res $1
modemLastDiscardReason: .res $1
modemPollTick: .res $1
modemTraceFrozen: .res $1
modemReceiveReadIndex: .res $1
modemReceiveWriteIndex: .res $1
modemTransmitReadIndex: .res $1
modemTransmitWriteIndex: .res $1
modemLastReceiveByte: .res $1
modemLastTransmitByte: .res $1
modemLastDataReport: .res $2
modemLastStatusReport: .res $2
modemTraceNextSequence: .res $4
modemReceiveAcceptedCount: .res $4
modemReceiveDiscardedCount: .res $4
modemTransmitByteCount: .res $4
modemReceiveOverflowCount: .res $4
modemTransmitOverflowCount: .res $4
modemPollBudgetYieldCount: .res $4
modemTimeoutCount: .res $4
modemReinitializeCount: .res $4
modemTraceOverwrittenCount: .res $4
modemResetStartFrame: .res $4
modemTerminalDroppedCount: .res $4
modemAtStatus: .res $1
modemAtExpectedResult: .res $1
modemSessionLastResult: .res $1
modemSessionLineLength: .res $1
modemAtStartFrame: .res $4
.res MODEM_DIAGNOSTIC_SIZE - (* - modemState)
modemStateEnd:

.assert modemDiagnosticMagic - modemState = MODEM_DIAG_MAGIC, error, "diagnostic magic offset"
.assert modemDiagnosticVersion - modemState = MODEM_DIAG_VERSION, error, "diagnostic version offset"
.assert modemDiagnosticSize - modemState = MODEM_DIAG_SIZE, error, "diagnostic size offset"
.assert modemSnapshotSequence - modemState = MODEM_DIAG_SNAPSHOT_SEQUENCE, error, "snapshot sequence offset"
.assert modemDriverState - modemState = MODEM_DIAG_DRIVER_STATE, error, "driver state offset"
.assert modemFlags - modemState = MODEM_DIAG_FLAGS, error, "flags offset"
.assert modemLastError - modemState = MODEM_DIAG_LAST_ERROR, error, "last error offset"
.assert modemLastDiscardReason - modemState = MODEM_DIAG_LAST_DISCARD_REASON, error, "discard reason offset"
.assert modemPollTick - modemState = MODEM_DIAG_POLL_TICK, error, "poll tick offset"
.assert modemTraceFrozen - modemState = MODEM_DIAG_TRACE_FROZEN, error, "trace frozen offset"
.assert modemReceiveReadIndex - modemState = MODEM_DIAG_RX_READ_INDEX, error, "RX read offset"
.assert modemReceiveWriteIndex - modemState = MODEM_DIAG_RX_WRITE_INDEX, error, "RX write offset"
.assert modemTransmitReadIndex - modemState = MODEM_DIAG_TX_READ_INDEX, error, "TX read offset"
.assert modemTransmitWriteIndex - modemState = MODEM_DIAG_TX_WRITE_INDEX, error, "TX write offset"
.assert modemLastReceiveByte - modemState = MODEM_DIAG_LAST_RX_BYTE, error, "last RX offset"
.assert modemLastTransmitByte - modemState = MODEM_DIAG_LAST_TX_BYTE, error, "last TX offset"
.assert modemLastDataReport - modemState = MODEM_DIAG_LAST_DATA_REPORT, error, "Data1 offset"
.assert modemLastStatusReport - modemState = MODEM_DIAG_LAST_STATUS_REPORT, error, "Data2 offset"
.assert modemTraceNextSequence - modemState = MODEM_DIAG_TRACE_NEXT_SEQUENCE, error, "trace sequence offset"
.assert modemReceiveAcceptedCount - modemState = MODEM_DIAG_RX_ACCEPTED, error, "RX accepted offset"
.assert modemReceiveDiscardedCount - modemState = MODEM_DIAG_RX_DISCARDED, error, "RX discarded offset"
.assert modemTransmitByteCount - modemState = MODEM_DIAG_TX_BYTES, error, "TX bytes offset"
.assert modemReceiveOverflowCount - modemState = MODEM_DIAG_RX_OVERFLOW, error, "RX overflow offset"
.assert modemTransmitOverflowCount - modemState = MODEM_DIAG_TX_OVERFLOW, error, "TX overflow offset"
.assert modemPollBudgetYieldCount - modemState = MODEM_DIAG_POLL_BUDGET_YIELD, error, "poll budget yield offset"
.assert modemTimeoutCount - modemState = MODEM_DIAG_TIMEOUT, error, "timeout offset"
.assert modemReinitializeCount - modemState = MODEM_DIAG_REINITIALIZE, error, "reinitialize offset"
.assert modemTraceOverwrittenCount - modemState = MODEM_DIAG_TRACE_OVERWRITTEN, error, "trace overwritten offset"
.assert modemResetStartFrame - modemState = MODEM_DIAG_RESET_START_FRAME, error, "reset frame offset"
.assert modemTerminalDroppedCount - modemState = MODEM_DIAG_TERMINAL_DROPPED, error, "terminal dropped offset"
.assert modemAtStatus - modemState = MODEM_DIAG_AT_STATUS, error, "AT status offset"
.assert modemAtExpectedResult - modemState = MODEM_DIAG_AT_EXPECTED_RESULT, error, "AT expected result offset"
.assert modemSessionLastResult - modemState = MODEM_DIAG_SESSION_LAST_RESULT, error, "session result offset"
.assert modemSessionLineLength - modemState = MODEM_DIAG_SESSION_LINE_LENGTH, error, "session line length offset"
.assert modemAtStartFrame - modemState = MODEM_DIAG_AT_START_FRAME, error, "AT start frame offset"
.assert modemStateEnd - modemState = MODEM_DIAGNOSTIC_SIZE, error, "diagnostic ABI size"

.export modemReceiveBuffer, modemTransmitBuffer
modemReceiveBuffer: .res MODEM_RING_STORAGE_SIZE
modemTransmitBuffer: .res MODEM_RING_STORAGE_SIZE

; QUsb2Snes test-control mailbox. The host writes hostSequence last. The SFC
; copies it to processedSequence only after the command result is committed.
.export modemMailbox, modemMailboxEnd
.export modemMailboxHostSequence, modemMailboxProcessedSequence
.export modemMailboxCommand, modemMailboxStatus, modemMailboxResult
.export modemMailboxArguments, modemMailboxOutput
modemMailbox:
modemMailboxMagic: .res $4
modemMailboxVersion: .res $2
modemMailboxSize: .res $2
modemMailboxHostSequence: .res $4
modemMailboxProcessedSequence: .res $4
modemMailboxCommand: .res $1
modemMailboxStatus: .res $1
modemMailboxResult: .res $2
modemMailboxArguments: .res MODEM_MAILBOX_ARGUMENT_SIZE
modemMailboxOutput: .res MODEM_MAILBOX_ARGUMENT_SIZE
.res MODEM_MAILBOX_SIZE - (* - modemMailbox)
modemMailboxEnd:
.assert modemMailboxMagic - modemMailbox = MODEM_MAILBOX_OFFSET_MAGIC, error, "mailbox magic offset"
.assert modemMailboxVersion - modemMailbox = MODEM_MAILBOX_OFFSET_VERSION, error, "mailbox version offset"
.assert modemMailboxSize - modemMailbox = MODEM_MAILBOX_OFFSET_BLOCK_SIZE, error, "mailbox size offset"
.assert modemMailboxHostSequence - modemMailbox = MODEM_MAILBOX_OFFSET_HOST_SEQUENCE, error, "mailbox host sequence offset"
.assert modemMailboxProcessedSequence - modemMailbox = MODEM_MAILBOX_OFFSET_PROCESSED_SEQUENCE, error, "mailbox processed sequence offset"
.assert modemMailboxCommand - modemMailbox = MODEM_MAILBOX_OFFSET_COMMAND, error, "mailbox command offset"
.assert modemMailboxStatus - modemMailbox = MODEM_MAILBOX_OFFSET_STATUS, error, "mailbox status offset"
.assert modemMailboxResult - modemMailbox = MODEM_MAILBOX_OFFSET_RESULT, error, "mailbox result offset"
.assert modemMailboxArguments - modemMailbox = MODEM_MAILBOX_OFFSET_ARGUMENTS, error, "mailbox arguments offset"
.assert modemMailboxOutput - modemMailbox = MODEM_MAILBOX_OFFSET_OUTPUT, error, "mailbox output offset"
.assert modemMailboxEnd - modemMailbox = MODEM_MAILBOX_SIZE, error, "mailbox ABI size"

.export modemTrace, modemTraceEnd
modemTrace: .res MODEM_TRACE_SIZE
modemTraceEnd:
.assert modemTraceEnd - modemTrace = MODEM_TRACE_SIZE, error, "trace ring size"

; Display-only mirror. It never owns application RX bytes. When full, the
; producer advances the read index so the newest terminal output is retained.
.export terminalDisplayReadIndex, terminalDisplayWriteIndex
.export terminalDisplayBuffer, terminalCursor, terminalVerticalScroll
.export terminalQueueScratchByte, terminalRenderScratchByte
terminalDisplayReadIndex: .res $1
terminalDisplayWriteIndex: .res $1
terminalDisplayBuffer: .res TERMINAL_QUEUE_STORAGE_SIZE
terminalDisplayBufferEnd:
terminalCursor: .res $2
terminalVerticalScroll: .res $2
terminalQueueScratchByte: .res $1
terminalRenderScratchByte: .res $1
.assert terminalDisplayBufferEnd - terminalDisplayBuffer = TERMINAL_QUEUE_STORAGE_SIZE, error, "terminal queue storage size"

; Human-facing status screen. The common renderer owns the connection page;
; the selected application dashboard owns the remaining protocol pages.
.segment "DISPLAY_BSS"

.export screenMode, statusPage, statusRenderedPage, statusDirectionLatch
.export statusTileBuffer, statusRenderRow, statusLastUpdateFrame
.export statusFormatValue, statusFormatStarted
screenMode: .res $1
statusPage: .res $1
statusRenderedPage: .res $1
statusDirectionLatch: .res $1
statusRenderRow: .res $1
statusLastUpdateFrame: .res $2
statusTileBuffer: .res TERMINAL_COLUMNS * TERMINAL_STATUS_ROWS
statusTileBufferEnd:
statusFormatValue: .res $2
statusFormatStarted: .res $1
.assert statusTileBufferEnd - statusTileBuffer = TERMINAL_COLUMNS * TERMINAL_STATUS_ROWS, error, "status tile buffer size"

; Software wall clock. Unix seconds remain UTC; the decomposed calendar is
; JST and is advanced from the nominal NTSC frame cadence after synchronization.
.export clockValid, clockUnixSeconds, clockSubsecond
.export clockLastFrame, clockYear, clockMonth, clockDay
.export clockHour, clockMinute, clockSecond, clockDisplayText
.export clockConversionRemaining
clockValid: .res $1
clockUnixSeconds: .res $4
clockSubsecond: .res $4
clockLastFrame: .res $2
clockYear: .res $2
clockMonth: .res $1
clockDay: .res $1
clockHour: .res $1
clockMinute: .res $1
clockSecond: .res $1
clockDisplayText: .res TERMINAL_COLUMNS - 7
clockConversionRemaining: .res $4

; Driver-private scratch state; never read by host tooling.
.segment "BSS"

.export modemTransferHadTransmit
modemTransferHadTransmit: .res $1
.export modemBurstPending
modemBurstPending: .res $1
.export modemTraceScratchKind
modemTraceScratchKind: .res $1
.export modemPollStage
modemPollStage: .res $1
.export modemSessionStage
modemSessionStage: .res $1
.export modemMailboxStage
modemMailboxStage: .res $1
.export modemMailboxObservedHost, modemMailboxObservedProcessed
modemMailboxObservedHost: .res $4
modemMailboxObservedProcessed: .res $4

; AT session state used while probing and for host-driven transactions.
.export modemSessionProbeSent, modemSessionRetryCount
.export modemSessionLine
.export modemSessionProbeStartFrame
.export modemAtTimeoutFrames
modemSessionProbeSent: .res $1
modemSessionRetryCount: .res $1
modemSessionLine: .res $20
modemSessionProbeStartFrame: .res $4
modemAtTimeoutFrames: .res $2

; transfer9 accesses this state through the bank $80 WRAM mirror.
.assert modemAtTimeoutFrames + $2 <= $7e2000, lderror, "NDM24 transfer state must remain in the first 8 KiB of WRAM"
