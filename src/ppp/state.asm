.include "constants.inc"

.bss

; RFC 1662 decoder state. These labels remain exported because QUsb2Snes
; diagnostics and later protocol layers inspect completed frames directly.
.export pppDecoderFlags, pppDecoderFcs, pppDecoderLength
.export pppLastEvent, pppLastInvalidReason, pppLastFrameLength
.export pppLastProtocol, pppFrameBuffer, pppFrameBufferEnd
.export pppDecoderScratchByte

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

