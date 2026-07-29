.include "../modem/generated.inc"
.include "constants.inc"

.bss

; Public, versioned PPP diagnostic ABI. Keep this layout synchronized with
; spec/ndm24.toml; the generated offsets are asserted below.
.export pppDiagnosticState, pppDiagnosticStateEnd
.export pppDiagnosticMagic, pppDiagnosticVersion, pppDiagnosticSize
.export pppSnapshotSequence
.export pppReceiveEnabled, pppReceiveActive, pppFrameReady
.export pppReceiveLastEvent, pppReceiveLastInvalidReason
.export pppDecoderFlags, pppDecoderFcs, pppDecoderLength
.export pppLastFrameLength, pppLastProtocol
.export pppTransmitActive, pppTransmitStage, pppTransmitEscapeSecond
.export pppTransmitLastWireByte, pppTransmitLength, pppTransmitPosition
.export pppTransmitFcs
.export pppReceiveByteCount, pppReceiveFrameCount, pppReceiveFcsErrorCount
.export pppReceiveInvalidCount, pppReceiveOverflowCount
.export pppReceiveDrainBudgetYieldCount
.export pppTransmitWireByteCount, pppTransmitFrameCount
.export pppTransmitBackpressureCount, pppTransmitAbortCount

pppDiagnosticState:
pppDiagnosticMagic: .res $4
pppDiagnosticVersion: .res $2
pppDiagnosticSize: .res $2
pppSnapshotSequence: .res $4
pppReceiveEnabled: .res $1
pppReceiveActive: .res $1
pppFrameReady: .res $1
pppReceiveLastEvent: .res $1
pppReceiveLastInvalidReason: .res $1
pppDecoderFlags: .res $1
pppTransmitActive: .res $1
pppTransmitStage: .res $1
pppTransmitEscapeSecond: .res $1
pppTransmitLastWireByte: .res $1
pppLastProtocol: .res $2
pppLastFrameLength: .res $2
pppDecoderLength: .res $2
pppDecoderFcs: .res $2
pppTransmitLength: .res $2
pppTransmitPosition: .res $2
pppTransmitFcs: .res $2
pppReceiveByteCount: .res $4
pppReceiveFrameCount: .res $4
pppReceiveFcsErrorCount: .res $4
pppReceiveInvalidCount: .res $4
pppReceiveOverflowCount: .res $4
pppReceiveDrainBudgetYieldCount: .res $4
pppTransmitWireByteCount: .res $4
pppTransmitFrameCount: .res $4
pppTransmitBackpressureCount: .res $4
pppTransmitAbortCount: .res $4
.res PPP_DIAGNOSTIC_SIZE - (* - pppDiagnosticState)
pppDiagnosticStateEnd:

.assert pppDiagnosticMagic - pppDiagnosticState = PPP_DIAG_MAGIC, error, "PPP diagnostic magic offset"
.assert pppDiagnosticVersion - pppDiagnosticState = PPP_DIAG_VERSION, error, "PPP diagnostic version offset"
.assert pppDiagnosticSize - pppDiagnosticState = PPP_DIAG_SIZE, error, "PPP diagnostic size offset"
.assert pppSnapshotSequence - pppDiagnosticState = PPP_DIAG_SNAPSHOT_SEQUENCE, error, "PPP snapshot sequence offset"
.assert pppReceiveEnabled - pppDiagnosticState = PPP_DIAG_RECEIVE_ENABLED, error, "PPP receive enabled offset"
.assert pppReceiveActive - pppDiagnosticState = PPP_DIAG_RECEIVE_ACTIVE, error, "PPP receive active offset"
.assert pppFrameReady - pppDiagnosticState = PPP_DIAG_FRAME_READY, error, "PPP frame ready offset"
.assert pppReceiveLastEvent - pppDiagnosticState = PPP_DIAG_RECEIVE_LAST_EVENT, error, "PPP receive event offset"
.assert pppReceiveLastInvalidReason - pppDiagnosticState = PPP_DIAG_RECEIVE_LAST_INVALID_REASON, error, "PPP invalid reason offset"
.assert pppDecoderFlags - pppDiagnosticState = PPP_DIAG_DECODER_FLAGS, error, "PPP decoder flags offset"
.assert pppTransmitActive - pppDiagnosticState = PPP_DIAG_TRANSMIT_ACTIVE, error, "PPP transmit active offset"
.assert pppTransmitStage - pppDiagnosticState = PPP_DIAG_TRANSMIT_STAGE, error, "PPP transmit stage offset"
.assert pppTransmitEscapeSecond - pppDiagnosticState = PPP_DIAG_TRANSMIT_ESCAPE_SECOND, error, "PPP transmit escape offset"
.assert pppTransmitLastWireByte - pppDiagnosticState = PPP_DIAG_TRANSMIT_LAST_WIRE_BYTE, error, "PPP last wire byte offset"
.assert pppLastProtocol - pppDiagnosticState = PPP_DIAG_LAST_PROTOCOL, error, "PPP protocol offset"
.assert pppLastFrameLength - pppDiagnosticState = PPP_DIAG_LAST_FRAME_LENGTH, error, "PPP frame length offset"
.assert pppDecoderLength - pppDiagnosticState = PPP_DIAG_DECODER_LENGTH, error, "PPP decoder length offset"
.assert pppDecoderFcs - pppDiagnosticState = PPP_DIAG_DECODER_FCS, error, "PPP decoder FCS offset"
.assert pppTransmitLength - pppDiagnosticState = PPP_DIAG_TRANSMIT_LENGTH, error, "PPP transmit length offset"
.assert pppTransmitPosition - pppDiagnosticState = PPP_DIAG_TRANSMIT_POSITION, error, "PPP transmit position offset"
.assert pppTransmitFcs - pppDiagnosticState = PPP_DIAG_TRANSMIT_FCS, error, "PPP transmit FCS offset"
.assert pppReceiveByteCount - pppDiagnosticState = PPP_DIAG_RECEIVE_BYTE_COUNT, error, "PPP receive byte count offset"
.assert pppReceiveFrameCount - pppDiagnosticState = PPP_DIAG_RECEIVE_FRAME_COUNT, error, "PPP receive frame count offset"
.assert pppReceiveFcsErrorCount - pppDiagnosticState = PPP_DIAG_RECEIVE_FCS_ERROR_COUNT, error, "PPP receive FCS error count offset"
.assert pppReceiveInvalidCount - pppDiagnosticState = PPP_DIAG_RECEIVE_INVALID_COUNT, error, "PPP receive invalid count offset"
.assert pppReceiveOverflowCount - pppDiagnosticState = PPP_DIAG_RECEIVE_OVERFLOW_COUNT, error, "PPP receive overflow count offset"
.assert pppReceiveDrainBudgetYieldCount - pppDiagnosticState = PPP_DIAG_RECEIVE_DRAIN_BUDGET_YIELD_COUNT, error, "PPP receive budget count offset"
.assert pppTransmitWireByteCount - pppDiagnosticState = PPP_DIAG_TRANSMIT_WIRE_BYTE_COUNT, error, "PPP transmit byte count offset"
.assert pppTransmitFrameCount - pppDiagnosticState = PPP_DIAG_TRANSMIT_FRAME_COUNT, error, "PPP transmit frame count offset"
.assert pppTransmitBackpressureCount - pppDiagnosticState = PPP_DIAG_TRANSMIT_BACKPRESSURE_COUNT, error, "PPP transmit backpressure count offset"
.assert pppTransmitAbortCount - pppDiagnosticState = PPP_DIAG_TRANSMIT_ABORT_COUNT, error, "PPP transmit abort count offset"
.assert pppDiagnosticStateEnd - pppDiagnosticState = PPP_DIAGNOSTIC_SIZE, error, "PPP diagnostic ABI size"

; Decoder and pump scratch fields are private and intentionally excluded from
; the host ABI.
.export pppLastEvent, pppLastInvalidReason, pppDecoderScratchByte
.export pppReceiveDrainRemaining
.export pppTransmitLogicalByte, pppTransmitFillRemaining
pppLastEvent: .res $1
pppLastInvalidReason: .res $1
pppDecoderScratchByte: .res $1
pppReceiveDrainRemaining: .res $1
pppTransmitLogicalByte: .res $1
pppTransmitFillRemaining: .res $1

; A nesting count lets the permanent self-test wrap lower-level routines that
; also publish state without ever exposing an even sequence mid-operation.
.export pppSnapshotDepth
pppSnapshotDepth: .res $1

.segment "PPP_BSS"

.export pppFrameBuffer, pppFrameBufferEnd
.export pppTransmitBuffer, pppTransmitBufferEnd
pppFrameBuffer: .res PPP_MAX_UNESCAPED_FRAME_LENGTH
pppFrameBufferEnd:
pppTransmitBuffer: .res PPP_MAX_TRANSMIT_FRAME_LENGTH
pppTransmitBufferEnd:

.assert pppFrameBufferEnd - pppFrameBuffer = PPP_MAX_UNESCAPED_FRAME_LENGTH, error, "PPP frame buffer size"
.assert pppTransmitBufferEnd - pppTransmitBuffer = PPP_MAX_TRANSMIT_FRAME_LENGTH, error, "PPP transmit buffer size"
