.include "constants.inc"

.bss

; RFC 1662 decoder state. These labels remain exported because QUsb2Snes
; diagnostics and later protocol layers inspect completed frames directly.
.export pppDecoderFlags, pppDecoderFcs, pppDecoderLength
.export pppLastEvent, pppLastInvalidReason, pppLastFrameLength
.export pppLastProtocol, pppFrameBuffer, pppFrameBufferEnd
.export pppDecoderScratchByte
.export pppReceiveEnabled, pppReceiveActive, pppFrameReady, pppReceiveLastEvent
.export pppReceiveLastInvalidReason, pppReceiveDrainRemaining
.export pppReceiveByteCount, pppReceiveFrameCount, pppReceiveFcsErrorCount
.export pppReceiveInvalidCount, pppReceiveOverflowCount
.export pppReceiveDrainBudgetYieldCount
.export pppTransmitActive, pppTransmitStage, pppTransmitEscapeSecond
.export pppTransmitLength, pppTransmitPosition, pppTransmitFcs
.export pppTransmitLogicalByte, pppTransmitFillRemaining
.export pppTransmitLastWireByte, pppTransmitWireByteCount
.export pppTransmitFrameCount, pppTransmitBackpressureCount
.export pppTransmitAbortCount
.export pppTransmitBuffer, pppTransmitBufferEnd

pppDecoderFlags: .res $1
pppLastEvent: .res $1
pppLastInvalidReason: .res $1
pppDecoderScratchByte: .res $1
pppDecoderFcs: .res $2
pppDecoderLength: .res $2
pppLastFrameLength: .res $2
pppLastProtocol: .res $2

.segment "PPP_BSS"

pppFrameBuffer: .res PPP_MAX_UNESCAPED_FRAME_LENGTH
pppFrameBufferEnd:
pppTransmitBuffer: .res PPP_MAX_TRANSMIT_FRAME_LENGTH
pppTransmitBufferEnd:

.assert pppFrameBufferEnd - pppFrameBuffer = PPP_MAX_UNESCAPED_FRAME_LENGTH, error, "PPP frame buffer size"
.assert pppTransmitBufferEnd - pppTransmitBuffer = PPP_MAX_TRANSMIT_FRAME_LENGTH, error, "PPP transmit buffer size"

.bss

; Receive-owner state and permanent counters. pppFrameReady transfers buffer
; ownership to the upper layer; no further RX bytes are consumed until it is
; explicitly released.
pppReceiveEnabled: .res $1
pppReceiveActive: .res $1
pppFrameReady: .res $1
pppReceiveLastEvent: .res $1
pppReceiveLastInvalidReason: .res $1
pppReceiveDrainRemaining: .res $1
pppReceiveByteCount: .res $4
pppReceiveFrameCount: .res $4
pppReceiveFcsErrorCount: .res $4
pppReceiveInvalidCount: .res $4
pppReceiveOverflowCount: .res $4
pppReceiveDrainBudgetYieldCount: .res $4

pppTransmitActive: .res $1
pppTransmitStage: .res $1
pppTransmitEscapeSecond: .res $1
pppTransmitLogicalByte: .res $1
pppTransmitFillRemaining: .res $1
pppTransmitLastWireByte: .res $1
pppTransmitLength: .res $2
pppTransmitPosition: .res $2
pppTransmitFcs: .res $2
pppTransmitWireByteCount: .res $4
pppTransmitFrameCount: .res $4
pppTransmitBackpressureCount: .res $4
pppTransmitAbortCount: .res $4
