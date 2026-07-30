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
.export pppIpv4LastError, pppIpv4HeaderLength, pppIpv4Protocol, pppIpv4Ttl
.export pppIpv4TotalLength, pppIpv4PayloadLength, pppIpv4Identification
.export pppIpv4FlagsFragmentOffset, pppIpv4HeaderChecksum
.export pppIpv4SourceAddress, pppIpv4DestinationAddress
.export pppIpv4ReceiveCount, pppIpv4AcceptedCount
.export pppIpv4ChecksumErrorCount, pppIpv4DropCount, pppIpv4TransmitCount
.export pppIpv4NextIdentification, pppIpv4Flags
.export pppIcmpLastError, pppIcmpLastType, pppIcmpLastCode, pppIcmpFlags
.export pppIcmpIdentifier, pppIcmpSequence, pppIcmpPayloadLength
.export pppIcmpChecksum, pppIcmpReceiveCount, pppIcmpEchoRequestCount
.export pppIcmpEchoReplyCount, pppIcmpChecksumErrorCount
.export pppIcmpDropCount, pppIcmpTransmitCount
.export pppUdpLastError, pppUdpFlags
.export pppUdpSourcePort, pppUdpDestinationPort
.export pppUdpLength, pppUdpPayloadLength, pppUdpChecksum
.export pppUdpReceiveCount, pppUdpChecksumErrorCount
.export pppUdpDropCount, pppUdpTransmitCount
.export pppNtpState, pppNtpLastError, pppNtpFlags, pppNtpVersion
.export pppNtpLeapIndicator, pppNtpStratum, pppNtpPollExponent, pppNtpPrecision
.export pppNtpReferenceId, pppNtpCookieSeconds, pppNtpCookieFraction
.export pppNtpServerReceiveSeconds, pppNtpServerReceiveFraction
.export pppNtpServerTransmitSeconds, pppNtpServerTransmitFraction
.export pppNtpUnixSeconds, pppNtpDeadline
.export pppNtpRequestCount, pppNtpResponseCount
.export pppNtpDropCount, pppNtpTimeoutCount
.export pppIcmpRequestState, pppIcmpRequestLastError, pppIcmpRequestFlags
.export pppIcmpRequestDestination
.export pppIcmpRequestIdentifier, pppIcmpRequestSequence
.export pppIcmpRequestDeadline, pppIcmpRequestSentFrame, pppIcmpRequestRttFrames
.export pppIcmpRequestCount, pppIcmpRequestResponseCount
.export pppIcmpRequestDropCount, pppIcmpRequestTimeoutCount
.export pppDnsState, pppDnsLastError, pppDnsFlags, pppDnsResponseCode
.export pppDnsResolver, pppDnsTransactionId, pppDnsAnswerCount
.export pppDnsAnswerAddress, pppDnsDeadline, pppDnsSentFrame, pppDnsRttFrames
.export pppDnsQueryCount, pppDnsResponseCount
.export pppDnsDropCount, pppDnsTimeoutCount
.export pppIcmpInboundState, pppIcmpInboundLastError, pppIcmpInboundFlags
.export pppIcmpInboundSource
.export pppIcmpInboundIdentifier, pppIcmpInboundSequence, pppIcmpInboundPayloadLength
.export pppIcmpInboundReplyCount, pppIcmpInboundDropCount
.export pppIpcpPrimaryDnsAddress, pppIpcpSecondaryDnsAddress

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
pppIpv4LastError: .res $1
pppIpv4HeaderLength: .res $1
pppIpv4Protocol: .res $1
pppIpv4Ttl: .res $1
pppIpv4TotalLength: .res $2
pppIpv4PayloadLength: .res $2
pppIpv4Identification: .res $2
pppIpv4FlagsFragmentOffset: .res $2
pppIpv4HeaderChecksum: .res $2
pppIpv4SourceAddress: .res $4
pppIpv4DestinationAddress: .res $4
pppIpv4ReceiveCount: .res $4
pppIpv4AcceptedCount: .res $4
pppIpv4ChecksumErrorCount: .res $4
pppIpv4DropCount: .res $4
pppIpv4TransmitCount: .res $4
pppIpv4NextIdentification: .res $2
pppIpv4Flags: .res $1
pppIcmpLastError: .res $1
pppIcmpLastType: .res $1
pppIcmpLastCode: .res $1
pppIcmpFlags: .res $1
pppIcmpIdentifier: .res $2
pppIcmpSequence: .res $2
pppIcmpPayloadLength: .res $2
pppIcmpChecksum: .res $2
pppIcmpReceiveCount: .res $4
pppIcmpEchoRequestCount: .res $4
pppIcmpEchoReplyCount: .res $4
pppIcmpChecksumErrorCount: .res $4
pppIcmpDropCount: .res $4
pppIcmpTransmitCount: .res $4
pppUdpLastError: .res $1
pppUdpFlags: .res $1
pppUdpSourcePort: .res $2
pppUdpDestinationPort: .res $2
pppUdpLength: .res $2
pppUdpPayloadLength: .res $2
pppUdpChecksum: .res $2
pppUdpReceiveCount: .res $4
pppUdpChecksumErrorCount: .res $4
pppUdpDropCount: .res $4
pppUdpTransmitCount: .res $4
pppNtpState: .res $1
pppNtpLastError: .res $1
pppNtpFlags: .res $1
pppNtpVersion: .res $1
pppNtpLeapIndicator: .res $1
pppNtpStratum: .res $1
pppNtpPollExponent: .res $1
pppNtpPrecision: .res $1
pppNtpReferenceId: .res $4
pppNtpCookieSeconds: .res $4
pppNtpCookieFraction: .res $4
pppNtpServerReceiveSeconds: .res $4
pppNtpServerReceiveFraction: .res $4
pppNtpServerTransmitSeconds: .res $4
pppNtpServerTransmitFraction: .res $4
pppNtpUnixSeconds: .res $4
pppNtpDeadline: .res $2
pppNtpRequestCount: .res $4
pppNtpResponseCount: .res $4
pppNtpDropCount: .res $4
pppNtpTimeoutCount: .res $4
pppIcmpRequestState: .res $1
pppIcmpRequestLastError: .res $1
pppIcmpRequestFlags: .res $1
pppIcmpRequestDestination: .res $4
pppIcmpRequestIdentifier: .res $2
pppIcmpRequestSequence: .res $2
pppIcmpRequestDeadline: .res $2
pppIcmpRequestSentFrame: .res $2
pppIcmpRequestRttFrames: .res $2
pppIcmpRequestCount: .res $4
pppIcmpRequestResponseCount: .res $4
pppIcmpRequestDropCount: .res $4
pppIcmpRequestTimeoutCount: .res $4
pppDnsState: .res $1
pppDnsLastError: .res $1
pppDnsFlags: .res $1
pppDnsResponseCode: .res $1
pppDnsResolver: .res $4
pppDnsTransactionId: .res $2
pppDnsAnswerCount: .res $2
pppDnsAnswerAddress: .res $4
pppDnsDeadline: .res $2
pppDnsSentFrame: .res $2
pppDnsRttFrames: .res $2
pppDnsQueryCount: .res $4
pppDnsResponseCount: .res $4
pppDnsDropCount: .res $4
pppDnsTimeoutCount: .res $4
pppIcmpInboundState: .res $1
pppIcmpInboundLastError: .res $1
pppIcmpInboundFlags: .res $1
pppIcmpInboundSource: .res $4
pppIcmpInboundIdentifier: .res $2
pppIcmpInboundSequence: .res $2
pppIcmpInboundPayloadLength: .res $2
pppIcmpInboundReplyCount: .res $4
pppIcmpInboundDropCount: .res $4
pppIpcpPrimaryDnsAddress: .res $4
pppIpcpSecondaryDnsAddress: .res $4
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
.assert pppIpv4LastError - pppDiagnosticState = PPP_DIAG_IPV4_LAST_ERROR, error, "PPP IPv4 error offset"
.assert pppIpv4HeaderLength - pppDiagnosticState = PPP_DIAG_IPV4_HEADER_LENGTH, error, "PPP IPv4 header length offset"
.assert pppIpv4Protocol - pppDiagnosticState = PPP_DIAG_IPV4_PROTOCOL, error, "PPP IPv4 protocol offset"
.assert pppIpv4Ttl - pppDiagnosticState = PPP_DIAG_IPV4_TTL, error, "PPP IPv4 TTL offset"
.assert pppIpv4TotalLength - pppDiagnosticState = PPP_DIAG_IPV4_TOTAL_LENGTH, error, "PPP IPv4 total length offset"
.assert pppIpv4PayloadLength - pppDiagnosticState = PPP_DIAG_IPV4_PAYLOAD_LENGTH, error, "PPP IPv4 payload length offset"
.assert pppIpv4Identification - pppDiagnosticState = PPP_DIAG_IPV4_IDENTIFICATION, error, "PPP IPv4 identification offset"
.assert pppIpv4FlagsFragmentOffset - pppDiagnosticState = PPP_DIAG_IPV4_FLAGS_FRAGMENT_OFFSET, error, "PPP IPv4 fragment offset"
.assert pppIpv4HeaderChecksum - pppDiagnosticState = PPP_DIAG_IPV4_HEADER_CHECKSUM, error, "PPP IPv4 checksum offset"
.assert pppIpv4SourceAddress - pppDiagnosticState = PPP_DIAG_IPV4_SOURCE_ADDRESS, error, "PPP IPv4 source offset"
.assert pppIpv4DestinationAddress - pppDiagnosticState = PPP_DIAG_IPV4_DESTINATION_ADDRESS, error, "PPP IPv4 destination offset"
.assert pppIpv4ReceiveCount - pppDiagnosticState = PPP_DIAG_IPV4_RECEIVE_COUNT, error, "PPP IPv4 receive count offset"
.assert pppIpv4AcceptedCount - pppDiagnosticState = PPP_DIAG_IPV4_ACCEPTED_COUNT, error, "PPP IPv4 accepted count offset"
.assert pppIpv4ChecksumErrorCount - pppDiagnosticState = PPP_DIAG_IPV4_CHECKSUM_ERROR_COUNT, error, "PPP IPv4 checksum error count offset"
.assert pppIpv4DropCount - pppDiagnosticState = PPP_DIAG_IPV4_DROP_COUNT, error, "PPP IPv4 drop count offset"
.assert pppIpv4TransmitCount - pppDiagnosticState = PPP_DIAG_IPV4_TRANSMIT_COUNT, error, "PPP IPv4 transmit count offset"
.assert pppIpv4NextIdentification - pppDiagnosticState = PPP_DIAG_IPV4_NEXT_IDENTIFICATION, error, "PPP IPv4 next identification offset"
.assert pppIpv4Flags - pppDiagnosticState = PPP_DIAG_IPV4_FLAGS, error, "PPP IPv4 flags offset"
.assert pppIcmpLastError - pppDiagnosticState = PPP_DIAG_ICMP_LAST_ERROR, error, "PPP ICMP error offset"
.assert pppIcmpLastType - pppDiagnosticState = PPP_DIAG_ICMP_LAST_TYPE, error, "PPP ICMP type offset"
.assert pppIcmpLastCode - pppDiagnosticState = PPP_DIAG_ICMP_LAST_CODE, error, "PPP ICMP code offset"
.assert pppIcmpFlags - pppDiagnosticState = PPP_DIAG_ICMP_FLAGS, error, "PPP ICMP flags offset"
.assert pppIcmpIdentifier - pppDiagnosticState = PPP_DIAG_ICMP_IDENTIFIER, error, "PPP ICMP identifier offset"
.assert pppIcmpSequence - pppDiagnosticState = PPP_DIAG_ICMP_SEQUENCE, error, "PPP ICMP sequence offset"
.assert pppIcmpPayloadLength - pppDiagnosticState = PPP_DIAG_ICMP_PAYLOAD_LENGTH, error, "PPP ICMP payload length offset"
.assert pppIcmpChecksum - pppDiagnosticState = PPP_DIAG_ICMP_CHECKSUM, error, "PPP ICMP checksum offset"
.assert pppIcmpReceiveCount - pppDiagnosticState = PPP_DIAG_ICMP_RECEIVE_COUNT, error, "PPP ICMP receive count offset"
.assert pppIcmpEchoRequestCount - pppDiagnosticState = PPP_DIAG_ICMP_ECHO_REQUEST_COUNT, error, "PPP ICMP request count offset"
.assert pppIcmpEchoReplyCount - pppDiagnosticState = PPP_DIAG_ICMP_ECHO_REPLY_COUNT, error, "PPP ICMP reply count offset"
.assert pppIcmpChecksumErrorCount - pppDiagnosticState = PPP_DIAG_ICMP_CHECKSUM_ERROR_COUNT, error, "PPP ICMP checksum error count offset"
.assert pppIcmpDropCount - pppDiagnosticState = PPP_DIAG_ICMP_DROP_COUNT, error, "PPP ICMP drop count offset"
.assert pppIcmpTransmitCount - pppDiagnosticState = PPP_DIAG_ICMP_TRANSMIT_COUNT, error, "PPP ICMP transmit count offset"
.assert pppUdpLastError - pppDiagnosticState = PPP_DIAG_UDP_LAST_ERROR, error, "PPP UDP error offset"
.assert pppUdpFlags - pppDiagnosticState = PPP_DIAG_UDP_FLAGS, error, "PPP UDP flags offset"
.assert pppUdpSourcePort - pppDiagnosticState = PPP_DIAG_UDP_SOURCE_PORT, error, "PPP UDP source port offset"
.assert pppUdpDestinationPort - pppDiagnosticState = PPP_DIAG_UDP_DESTINATION_PORT, error, "PPP UDP destination port offset"
.assert pppUdpLength - pppDiagnosticState = PPP_DIAG_UDP_LENGTH, error, "PPP UDP length offset"
.assert pppUdpPayloadLength - pppDiagnosticState = PPP_DIAG_UDP_PAYLOAD_LENGTH, error, "PPP UDP payload length offset"
.assert pppUdpChecksum - pppDiagnosticState = PPP_DIAG_UDP_CHECKSUM, error, "PPP UDP checksum offset"
.assert pppUdpReceiveCount - pppDiagnosticState = PPP_DIAG_UDP_RECEIVE_COUNT, error, "PPP UDP receive count offset"
.assert pppUdpChecksumErrorCount - pppDiagnosticState = PPP_DIAG_UDP_CHECKSUM_ERROR_COUNT, error, "PPP UDP checksum error count offset"
.assert pppUdpDropCount - pppDiagnosticState = PPP_DIAG_UDP_DROP_COUNT, error, "PPP UDP drop count offset"
.assert pppUdpTransmitCount - pppDiagnosticState = PPP_DIAG_UDP_TRANSMIT_COUNT, error, "PPP UDP transmit count offset"
.assert pppNtpState - pppDiagnosticState = PPP_DIAG_NTP_STATE, error, "PPP NTP state offset"
.assert pppNtpLastError - pppDiagnosticState = PPP_DIAG_NTP_LAST_ERROR, error, "PPP NTP error offset"
.assert pppNtpFlags - pppDiagnosticState = PPP_DIAG_NTP_FLAGS, error, "PPP NTP flags offset"
.assert pppNtpVersion - pppDiagnosticState = PPP_DIAG_NTP_VERSION, error, "PPP NTP version offset"
.assert pppNtpLeapIndicator - pppDiagnosticState = PPP_DIAG_NTP_LEAP_INDICATOR, error, "PPP NTP leap offset"
.assert pppNtpStratum - pppDiagnosticState = PPP_DIAG_NTP_STRATUM, error, "PPP NTP stratum offset"
.assert pppNtpPollExponent - pppDiagnosticState = PPP_DIAG_NTP_POLL, error, "PPP NTP poll offset"
.assert pppNtpPrecision - pppDiagnosticState = PPP_DIAG_NTP_PRECISION, error, "PPP NTP precision offset"
.assert pppNtpReferenceId - pppDiagnosticState = PPP_DIAG_NTP_REFERENCE_ID, error, "PPP NTP reference ID offset"
.assert pppNtpCookieSeconds - pppDiagnosticState = PPP_DIAG_NTP_COOKIE_SECONDS, error, "PPP NTP cookie seconds offset"
.assert pppNtpCookieFraction - pppDiagnosticState = PPP_DIAG_NTP_COOKIE_FRACTION, error, "PPP NTP cookie fraction offset"
.assert pppNtpServerReceiveSeconds - pppDiagnosticState = PPP_DIAG_NTP_SERVER_RECEIVE_SECONDS, error, "PPP NTP receive seconds offset"
.assert pppNtpServerReceiveFraction - pppDiagnosticState = PPP_DIAG_NTP_SERVER_RECEIVE_FRACTION, error, "PPP NTP receive fraction offset"
.assert pppNtpServerTransmitSeconds - pppDiagnosticState = PPP_DIAG_NTP_SERVER_TRANSMIT_SECONDS, error, "PPP NTP transmit seconds offset"
.assert pppNtpServerTransmitFraction - pppDiagnosticState = PPP_DIAG_NTP_SERVER_TRANSMIT_FRACTION, error, "PPP NTP transmit fraction offset"
.assert pppNtpUnixSeconds - pppDiagnosticState = PPP_DIAG_NTP_UNIX_SECONDS, error, "PPP NTP Unix seconds offset"
.assert pppNtpDeadline - pppDiagnosticState = PPP_DIAG_NTP_DEADLINE, error, "PPP NTP deadline offset"
.assert pppNtpRequestCount - pppDiagnosticState = PPP_DIAG_NTP_REQUEST_COUNT, error, "PPP NTP request count offset"
.assert pppNtpResponseCount - pppDiagnosticState = PPP_DIAG_NTP_RESPONSE_COUNT, error, "PPP NTP response count offset"
.assert pppNtpDropCount - pppDiagnosticState = PPP_DIAG_NTP_DROP_COUNT, error, "PPP NTP drop count offset"
.assert pppNtpTimeoutCount - pppDiagnosticState = PPP_DIAG_NTP_TIMEOUT_COUNT, error, "PPP NTP timeout count offset"
.assert pppIcmpRequestState - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_STATE, error, "PPP ICMP request state offset"
.assert pppIcmpRequestLastError - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_LAST_ERROR, error, "PPP ICMP request error offset"
.assert pppIcmpRequestFlags - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_FLAGS, error, "PPP ICMP request flags offset"
.assert pppIcmpRequestDestination - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_DESTINATION, error, "PPP ICMP request destination offset"
.assert pppIcmpRequestIdentifier - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_IDENTIFIER, error, "PPP ICMP request identifier offset"
.assert pppIcmpRequestSequence - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_SEQUENCE, error, "PPP ICMP request sequence offset"
.assert pppIcmpRequestDeadline - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_DEADLINE, error, "PPP ICMP request deadline offset"
.assert pppIcmpRequestSentFrame - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_SENT_FRAME, error, "PPP ICMP request sent frame offset"
.assert pppIcmpRequestRttFrames - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_RTT_FRAMES, error, "PPP ICMP request RTT offset"
.assert pppIcmpRequestCount - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_COUNT, error, "PPP ICMP request count offset"
.assert pppIcmpRequestResponseCount - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_RESPONSE_COUNT, error, "PPP ICMP request response count offset"
.assert pppIcmpRequestDropCount - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_DROP_COUNT, error, "PPP ICMP request drop count offset"
.assert pppIcmpRequestTimeoutCount - pppDiagnosticState = PPP_DIAG_ICMP_REQUEST_TIMEOUT_COUNT, error, "PPP ICMP request timeout count offset"
.assert pppDnsState - pppDiagnosticState = PPP_DIAG_DNS_STATE, error, "PPP DNS state offset"
.assert pppDnsLastError - pppDiagnosticState = PPP_DIAG_DNS_LAST_ERROR, error, "PPP DNS error offset"
.assert pppDnsFlags - pppDiagnosticState = PPP_DIAG_DNS_FLAGS, error, "PPP DNS flags offset"
.assert pppDnsResponseCode - pppDiagnosticState = PPP_DIAG_DNS_RESPONSE_CODE, error, "PPP DNS response code offset"
.assert pppDnsResolver - pppDiagnosticState = PPP_DIAG_DNS_RESOLVER, error, "PPP DNS resolver offset"
.assert pppDnsTransactionId - pppDiagnosticState = PPP_DIAG_DNS_TRANSACTION_ID, error, "PPP DNS transaction offset"
.assert pppDnsAnswerCount - pppDiagnosticState = PPP_DIAG_DNS_ANSWER_COUNT, error, "PPP DNS answer count offset"
.assert pppDnsAnswerAddress - pppDiagnosticState = PPP_DIAG_DNS_ANSWER_ADDRESS, error, "PPP DNS answer address offset"
.assert pppDnsDeadline - pppDiagnosticState = PPP_DIAG_DNS_DEADLINE, error, "PPP DNS deadline offset"
.assert pppDnsSentFrame - pppDiagnosticState = PPP_DIAG_DNS_SENT_FRAME, error, "PPP DNS sent frame offset"
.assert pppDnsRttFrames - pppDiagnosticState = PPP_DIAG_DNS_RTT_FRAMES, error, "PPP DNS RTT offset"
.assert pppDnsQueryCount - pppDiagnosticState = PPP_DIAG_DNS_QUERY_COUNT, error, "PPP DNS query count offset"
.assert pppDnsResponseCount - pppDiagnosticState = PPP_DIAG_DNS_RESPONSE_COUNT, error, "PPP DNS response count offset"
.assert pppDnsDropCount - pppDiagnosticState = PPP_DIAG_DNS_DROP_COUNT, error, "PPP DNS drop count offset"
.assert pppDnsTimeoutCount - pppDiagnosticState = PPP_DIAG_DNS_TIMEOUT_COUNT, error, "PPP DNS timeout count offset"
.assert pppIcmpInboundState - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_STATE, error, "PPP inbound ICMP state offset"
.assert pppIcmpInboundLastError - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_LAST_ERROR, error, "PPP inbound ICMP error offset"
.assert pppIcmpInboundFlags - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_FLAGS, error, "PPP inbound ICMP flags offset"
.assert pppIcmpInboundSource - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_SOURCE, error, "PPP inbound ICMP source offset"
.assert pppIcmpInboundIdentifier - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_IDENTIFIER, error, "PPP inbound ICMP identifier offset"
.assert pppIcmpInboundSequence - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_SEQUENCE, error, "PPP inbound ICMP sequence offset"
.assert pppIcmpInboundPayloadLength - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_PAYLOAD_LENGTH, error, "PPP inbound ICMP payload offset"
.assert pppIcmpInboundReplyCount - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_REPLY_COUNT, error, "PPP inbound ICMP reply count offset"
.assert pppIcmpInboundDropCount - pppDiagnosticState = PPP_DIAG_ICMP_INBOUND_DROP_COUNT, error, "PPP inbound ICMP drop count offset"
.assert pppIpcpPrimaryDnsAddress - pppDiagnosticState = PPP_DIAG_IPCP_PRIMARY_DNS_ADDRESS, error, "PPP IPCP primary DNS offset"
.assert pppIpcpSecondaryDnsAddress - pppDiagnosticState = PPP_DIAG_IPCP_SECONDARY_DNS_ADDRESS, error, "PPP IPCP secondary DNS offset"
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
.export pppIpv4ChecksumAccumulator, pppIpv4AvailableLength
.export pppIpv4TransmitDestination, pppIpv4TransmitProtocol
.export pppIpv4TransmitPayloadLength, pppIpv4PollSavedModemState
.export pppIcmpPacketOffset, pppIcmpChecksumAccumulator
.export pppIcmpRequestTestSavedFrameCounter
.export pppUdpPacketOffset, pppUdpChecksumAccumulator
.export pppUdpTransmitSourcePort, pppUdpTransmitDestinationPort
.export pppNtpPacketOffset, pppNtpTestSavedFrameCounter
.export pppNtpTestSavedClockValid, pppNtpTestSavedClockSeconds
.export pppNtpTestSavedClockSubsecond
.export pppDnsQueryName, pppDnsQueryNameLength
.export pppDnsPacketOffset, pppDnsPacketEnd, pppDnsCursor
.export pppDnsRecordRemaining, pppDnsDataLength
.export pppDnsQueryCursor, pppDnsLabelPosition, pppDnsLabelLength
.export pppDnsTestSavedFrameCounter
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
pppIpv4ChecksumAccumulator: .res $2
pppIpv4AvailableLength: .res $2
pppIpv4TransmitDestination: .res $4
pppIpv4TransmitProtocol: .res $1
pppIpv4TransmitPayloadLength: .res $2
pppIpv4PollSavedModemState: .res $1
pppIcmpPacketOffset: .res $2
pppIcmpChecksumAccumulator: .res $2
pppIcmpRequestTestSavedFrameCounter: .res $4
pppUdpPacketOffset: .res $2
pppUdpChecksumAccumulator: .res $2
pppUdpTransmitSourcePort: .res $2
pppUdpTransmitDestinationPort: .res $2
pppNtpPacketOffset: .res $2
pppNtpTestSavedFrameCounter: .res $4
pppNtpTestSavedClockValid: .res $1
pppNtpTestSavedClockSeconds: .res $4
pppNtpTestSavedClockSubsecond: .res $4
pppDnsQueryName: .res PPP_DNS_MAXIMUM_NAME_LENGTH
pppDnsQueryNameLength: .res $1
pppDnsPacketOffset: .res $2
pppDnsPacketEnd: .res $2
pppDnsCursor: .res $2
pppDnsRecordRemaining: .res $2
pppDnsDataLength: .res $2
pppDnsQueryCursor: .res $2
pppDnsLabelPosition: .res $2
pppDnsLabelLength: .res $1
pppDnsTestSavedFrameCounter: .res $4
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
