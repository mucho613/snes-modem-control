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
.export pppLcpState, pppLcpLastCode, pppLcpLastIdentifier
.export pppLcpLastError, pppLcpRequestIdentifier, pppLcpRestartRemaining
.export pppLcpPeerFlags, pppLcpPendingAction, pppLcpPacketLength
.export pppLcpPeerMru, pppLcpPeerAccm, pppLcpReceiveCount
.export pppLcpTimerActive, pppLcpDeferredRequest
.export pppLcpRestartDeadline, pppLcpPeerMagic
.export pppCarrierLossCount, pppCarrierTailByteCount
.export pppPapState, pppPapLastCode, pppPapLastIdentifier, pppPapLastError
.export pppPapRequestIdentifier, pppPapNextIdentifier
.export pppPapRestartRemaining, pppPapPendingAction
.export pppPapTimerActive, pppPapFailure, pppPapPacketLength
.export pppPapRestartDeadline, pppPapReceiveCount, pppPapTransmitCount
.export pppIpcpState, pppIpcpLastCode, pppIpcpLastIdentifier
.export pppIpcpLastError, pppIpcpRequestIdentifier, pppIpcpRestartRemaining
.export pppIpcpPendingAction, pppIpcpTimerActive, pppIpcpPacketLength
.export pppIpcpRestartDeadline, pppIpcpReceiveCount, pppIpcpTransmitCount
.export pppIpcpLocalAddress, pppIpcpPeerAddress, pppIpcpFlags
.export pppIpcpDeferredRequest

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
pppLcpState: .res $1
pppLcpLastCode: .res $1
pppLcpLastIdentifier: .res $1
pppLcpLastError: .res $1
pppLcpRequestIdentifier: .res $1
pppLcpRestartRemaining: .res $1
pppLcpPeerFlags: .res $1
pppLcpPendingAction: .res $1
pppLcpPacketLength: .res $2
pppLcpPeerMru: .res $2
pppLcpPeerAccm: .res $4
pppLcpReceiveCount: .res $4
pppLcpTimerActive: .res $1
pppLcpDeferredRequest: .res $1
pppLcpRestartDeadline: .res $2
pppLcpPeerMagic: .res $4
pppCarrierLossCount: .res $4
pppCarrierTailByteCount: .res $4
pppPapState: .res $1
pppPapLastCode: .res $1
pppPapLastIdentifier: .res $1
pppPapLastError: .res $1
pppPapRequestIdentifier: .res $1
pppPapNextIdentifier: .res $1
pppPapRestartRemaining: .res $1
pppPapPendingAction: .res $1
pppPapTimerActive: .res $1
pppPapFailure: .res $1
pppPapPacketLength: .res $2
pppPapRestartDeadline: .res $2
pppPapReceiveCount: .res $4
pppPapTransmitCount: .res $4
pppIpcpState: .res $1
pppIpcpLastCode: .res $1
pppIpcpLastIdentifier: .res $1
pppIpcpLastError: .res $1
pppIpcpRequestIdentifier: .res $1
pppIpcpRestartRemaining: .res $1
pppIpcpPendingAction: .res $1
pppIpcpTimerActive: .res $1
pppIpcpPacketLength: .res $2
pppIpcpRestartDeadline: .res $2
pppIpcpReceiveCount: .res $4
pppIpcpTransmitCount: .res $4
pppIpcpLocalAddress: .res $4
pppIpcpPeerAddress: .res $4
pppIpcpFlags: .res $1
pppIpcpDeferredRequest: .res $1
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
.assert pppLcpState - pppDiagnosticState = PPP_DIAG_LCP_STATE, error, "PPP LCP state offset"
.assert pppLcpLastCode - pppDiagnosticState = PPP_DIAG_LCP_LAST_CODE, error, "PPP LCP code offset"
.assert pppLcpLastIdentifier - pppDiagnosticState = PPP_DIAG_LCP_LAST_IDENTIFIER, error, "PPP LCP identifier offset"
.assert pppLcpLastError - pppDiagnosticState = PPP_DIAG_LCP_LAST_ERROR, error, "PPP LCP error offset"
.assert pppLcpRequestIdentifier - pppDiagnosticState = PPP_DIAG_LCP_REQUEST_IDENTIFIER, error, "PPP LCP request identifier offset"
.assert pppLcpRestartRemaining - pppDiagnosticState = PPP_DIAG_LCP_RESTART_REMAINING, error, "PPP LCP restart offset"
.assert pppLcpPeerFlags - pppDiagnosticState = PPP_DIAG_LCP_PEER_FLAGS, error, "PPP LCP peer flags offset"
.assert pppLcpPendingAction - pppDiagnosticState = PPP_DIAG_LCP_PENDING_ACTION, error, "PPP LCP pending action offset"
.assert pppLcpPacketLength - pppDiagnosticState = PPP_DIAG_LCP_PACKET_LENGTH, error, "PPP LCP packet length offset"
.assert pppLcpPeerMru - pppDiagnosticState = PPP_DIAG_LCP_PEER_MRU, error, "PPP LCP peer MRU offset"
.assert pppLcpPeerAccm - pppDiagnosticState = PPP_DIAG_LCP_PEER_ACCM, error, "PPP LCP peer ACCM offset"
.assert pppLcpReceiveCount - pppDiagnosticState = PPP_DIAG_LCP_RECEIVE_COUNT, error, "PPP LCP receive count offset"
.assert pppLcpTimerActive - pppDiagnosticState = PPP_DIAG_LCP_TIMER_ACTIVE, error, "PPP LCP timer active offset"
.assert pppLcpDeferredRequest - pppDiagnosticState = PPP_DIAG_LCP_DEFERRED_REQUEST, error, "PPP LCP deferred request offset"
.assert pppLcpRestartDeadline - pppDiagnosticState = PPP_DIAG_LCP_RESTART_DEADLINE, error, "PPP LCP restart deadline offset"
.assert pppLcpPeerMagic - pppDiagnosticState = PPP_DIAG_LCP_PEER_MAGIC, error, "PPP LCP peer magic offset"
.assert pppCarrierLossCount - pppDiagnosticState = PPP_DIAG_CARRIER_LOSS_COUNT, error, "PPP carrier loss count offset"
.assert pppCarrierTailByteCount - pppDiagnosticState = PPP_DIAG_CARRIER_TAIL_BYTE_COUNT, error, "PPP carrier tail byte count offset"
.assert pppPapState - pppDiagnosticState = PPP_DIAG_PAP_STATE, error, "PPP PAP state offset"
.assert pppPapLastCode - pppDiagnosticState = PPP_DIAG_PAP_LAST_CODE, error, "PPP PAP code offset"
.assert pppPapLastIdentifier - pppDiagnosticState = PPP_DIAG_PAP_LAST_IDENTIFIER, error, "PPP PAP identifier offset"
.assert pppPapLastError - pppDiagnosticState = PPP_DIAG_PAP_LAST_ERROR, error, "PPP PAP error offset"
.assert pppPapRequestIdentifier - pppDiagnosticState = PPP_DIAG_PAP_REQUEST_IDENTIFIER, error, "PPP PAP request identifier offset"
.assert pppPapNextIdentifier - pppDiagnosticState = PPP_DIAG_PAP_NEXT_IDENTIFIER, error, "PPP PAP next identifier offset"
.assert pppPapRestartRemaining - pppDiagnosticState = PPP_DIAG_PAP_RESTART_REMAINING, error, "PPP PAP restart offset"
.assert pppPapPendingAction - pppDiagnosticState = PPP_DIAG_PAP_PENDING_ACTION, error, "PPP PAP pending action offset"
.assert pppPapTimerActive - pppDiagnosticState = PPP_DIAG_PAP_TIMER_ACTIVE, error, "PPP PAP timer active offset"
.assert pppPapFailure - pppDiagnosticState = PPP_DIAG_PAP_FAILURE, error, "PPP PAP failure offset"
.assert pppPapPacketLength - pppDiagnosticState = PPP_DIAG_PAP_PACKET_LENGTH, error, "PPP PAP packet length offset"
.assert pppPapRestartDeadline - pppDiagnosticState = PPP_DIAG_PAP_RESTART_DEADLINE, error, "PPP PAP deadline offset"
.assert pppPapReceiveCount - pppDiagnosticState = PPP_DIAG_PAP_RECEIVE_COUNT, error, "PPP PAP receive count offset"
.assert pppPapTransmitCount - pppDiagnosticState = PPP_DIAG_PAP_TRANSMIT_COUNT, error, "PPP PAP transmit count offset"
.assert pppIpcpState - pppDiagnosticState = PPP_DIAG_IPCP_STATE, error, "PPP IPCP state offset"
.assert pppIpcpLastCode - pppDiagnosticState = PPP_DIAG_IPCP_LAST_CODE, error, "PPP IPCP code offset"
.assert pppIpcpLastIdentifier - pppDiagnosticState = PPP_DIAG_IPCP_LAST_IDENTIFIER, error, "PPP IPCP identifier offset"
.assert pppIpcpLastError - pppDiagnosticState = PPP_DIAG_IPCP_LAST_ERROR, error, "PPP IPCP error offset"
.assert pppIpcpRequestIdentifier - pppDiagnosticState = PPP_DIAG_IPCP_REQUEST_IDENTIFIER, error, "PPP IPCP request identifier offset"
.assert pppIpcpRestartRemaining - pppDiagnosticState = PPP_DIAG_IPCP_RESTART_REMAINING, error, "PPP IPCP restart offset"
.assert pppIpcpPendingAction - pppDiagnosticState = PPP_DIAG_IPCP_PENDING_ACTION, error, "PPP IPCP pending action offset"
.assert pppIpcpTimerActive - pppDiagnosticState = PPP_DIAG_IPCP_TIMER_ACTIVE, error, "PPP IPCP timer offset"
.assert pppIpcpPacketLength - pppDiagnosticState = PPP_DIAG_IPCP_PACKET_LENGTH, error, "PPP IPCP packet length offset"
.assert pppIpcpRestartDeadline - pppDiagnosticState = PPP_DIAG_IPCP_RESTART_DEADLINE, error, "PPP IPCP deadline offset"
.assert pppIpcpReceiveCount - pppDiagnosticState = PPP_DIAG_IPCP_RECEIVE_COUNT, error, "PPP IPCP receive count offset"
.assert pppIpcpTransmitCount - pppDiagnosticState = PPP_DIAG_IPCP_TRANSMIT_COUNT, error, "PPP IPCP transmit count offset"
.assert pppIpcpLocalAddress - pppDiagnosticState = PPP_DIAG_IPCP_LOCAL_ADDRESS, error, "PPP IPCP local address offset"
.assert pppIpcpPeerAddress - pppDiagnosticState = PPP_DIAG_IPCP_PEER_ADDRESS, error, "PPP IPCP peer address offset"
.assert pppIpcpFlags - pppDiagnosticState = PPP_DIAG_IPCP_FLAGS, error, "PPP IPCP flags offset"
.assert pppIpcpDeferredRequest - pppDiagnosticState = PPP_DIAG_IPCP_DEFERRED_REQUEST, error, "PPP IPCP deferred request offset"
.assert pppDiagnosticStateEnd - pppDiagnosticState = PPP_DIAGNOSTIC_SIZE, error, "PPP diagnostic ABI size"

; Decoder and pump scratch fields are private and intentionally excluded from
; the host ABI.
.export pppLastEvent, pppLastInvalidReason, pppDecoderScratchByte
.export pppReceiveDrainRemaining
.export pppTransmitLogicalByte, pppTransmitFillRemaining
.export pppLcpPacketEnd, pppLcpOptionLength
.export pppLcpOptionSeen, pppLcpOptionDuplicate
.export pppLcpOptionOffset, pppLcpOutputCursor
.export pppLcpHasReject, pppLcpHasNak
.export pppLcpPollAction
.export pppLcpPollSavedModemState
.export pppCarrierLineIndex, pppCarrierScratchByte
.export pppCarrierTestSavedModemState, pppCarrierTestSavedSessionResult
.export pppCarrierTestSavedLineLength
.export pppIpcpPacketEnd, pppIpcpOptionLength, pppIpcpOptionOffset
.export pppIpcpOutputCursor, pppIpcpHasReject, pppIpcpHasNak
.export pppIpcpOptionSeen, pppIpcpOptionDuplicate, pppIpcpPollAction
.export pppIpcpPollSavedModemState
pppLastEvent: .res $1
pppLastInvalidReason: .res $1
pppDecoderScratchByte: .res $1
pppReceiveDrainRemaining: .res $1
pppTransmitLogicalByte: .res $1
pppTransmitFillRemaining: .res $1
pppLcpPacketEnd: .res $2
pppLcpOptionLength: .res $2
pppLcpOptionOffset: .res $2
pppLcpOutputCursor: .res $2
pppLcpHasReject: .res $1
pppLcpHasNak: .res $1
pppLcpPollAction: .res $1
pppLcpPollSavedModemState: .res $1
pppCarrierLineIndex: .res $1
pppCarrierScratchByte: .res $1
pppCarrierTestSavedModemState: .res $1
pppCarrierTestSavedSessionResult: .res $1
pppCarrierTestSavedLineLength: .res $1
pppIpcpPacketEnd: .res $2
pppIpcpOptionLength: .res $2
pppIpcpOptionOffset: .res $2
pppIpcpOutputCursor: .res $2
pppIpcpHasReject: .res $1
pppIpcpHasNak: .res $1
pppIpcpPollAction: .res $1
pppIpcpPollSavedModemState: .res $1
pppLcpOptionSeen: .res $100
pppLcpOptionDuplicate: .res $100
pppIpcpOptionSeen: .res $100
pppIpcpOptionDuplicate: .res $100

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
