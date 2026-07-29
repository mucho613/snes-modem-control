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

pppDecoderFlags: .res $1
pppLastEvent: .res $1
pppLastInvalidReason: .res $1
pppDecoderScratchByte: .res $1
pppDecoderFcs: .res $2
pppDecoderLength: .res $2
pppLastFrameLength: .res $2
pppLastProtocol: .res $2
pppFrameBuffer: .res PPP_MAX_UNESCAPED_FRAME_LENGTH
pppFrameBufferEnd:

.assert pppFrameBufferEnd - pppFrameBuffer = PPP_MAX_UNESCAPED_FRAME_LENGTH, error, "PPP frame buffer size"

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
