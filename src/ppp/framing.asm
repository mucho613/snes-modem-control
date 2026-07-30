.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppDecoderFlags, pppDecoderFcs, pppDecoderLength
.import pppLastEvent, pppLastInvalidReason, pppLastFrameLength
.import pppLastProtocol, pppFrameBuffer, pppDecoderScratchByte

.export pppDecoderReset, pppDecoderPush, pppDecoderDiscardPartial

; Reset the stream decoder. The first Flag Sequence after reset establishes
; synchronization and does not report an empty frame.
.proc pppDecoderReset
  .a8
  .i16

  phb
  setDBR $7e

  stz pppDecoderFlags
  stz pppLastEvent
  stz pppLastInvalidReason
  stz pppLastFrameLength
  stz pppLastFrameLength + 1
  stz pppLastProtocol
  stz pppLastProtocol + 1
  jsr pppPrepareNextFrame

  plb
  rts
.endproc

; Discard an incomplete frame at a confirmed modem result-line boundary while
; preserving the most recent completed frame diagnostics.
.proc pppDecoderDiscardPartial
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppPrepareNextFrame
  plb
  rts
.endproc

; Consume one raw asynchronous PPP octet.
;
; Input:
;   A = raw octet
; Output:
;   A = PPP_EVENT_*
; Preserves:
;   X, Y, DBR
;
; The initial receive ACCM is $FFFFFFFF. Consequently, unescaped raw control
; octets $00-$1F are removed before escape processing and FCS calculation.
.proc pppDecoderPush
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e

  sta pppDecoderScratchByte
  stz pppLastEvent

  cmp #PPP_FLAG_SEQUENCE
  bne @notFlag
  jsr pppFinishAtFlag
  jmp @return

@notFlag:
  lda pppDecoderFlags
  bit #PPP_DECODER_FLAG_SYNCHRONIZED
  beq @return
  bit #PPP_DECODER_FLAG_OVERFLOWED
  bne @return

  ; RFC 1662 section 4.2 removes receive-ACCM control octets before
  ; unescaping. An escape remains pending if an injected control is removed.
  lda pppDecoderScratchByte
  cmp #$20
  bcc @return

  lda pppDecoderFlags
  bit #PPP_DECODER_FLAG_ESCAPED
  beq @checkEscape
  and #($ff ^ PPP_DECODER_FLAG_ESCAPED)
  sta pppDecoderFlags
  lda pppDecoderScratchByte
  eor #PPP_TRANSPARENCY_XOR
  sta pppDecoderScratchByte
  bra @append

@checkEscape:
  lda pppDecoderScratchByte
  cmp #PPP_CONTROL_ESCAPE
  bne @append
  lda pppDecoderFlags
  ora #PPP_DECODER_FLAG_ESCAPED
  sta pppDecoderFlags
  bra @return

@append:
  m16
  lda pppDecoderLength
  cmp #PPP_MAX_UNESCAPED_FRAME_LENGTH
  bcc @hasSpace

  m8
  lda pppDecoderFlags
  ora #PPP_DECODER_FLAG_OVERFLOWED
  sta pppDecoderFlags
  stz pppDecoderLength
  stz pppDecoderLength + 1
  bra @return

@hasSpace:
  tax
  m8
  lda pppDecoderScratchByte
  sta pppFrameBuffer, x
  jsr pppUpdateFcs
  m16
  inc pppDecoderLength
  m8
@return:
  lda pppLastEvent
  ply
  plx
  plb
  rts
.endproc

; Update pppDecoderFcs with pppDecoderScratchByte. This bitwise form mirrors
; the Rust reference implementation and RFC 1662 Appendix C.2.
.proc pppUpdateFcs
  .a8
  .i16

  lda pppDecoderScratchByte
  m16
  and #$00ff
  eor pppDecoderFcs
  sta pppDecoderFcs

  ldx #$0008
@bit:
  lda pppDecoderFcs
  lsr
  bcc @store
  eor #PPP_FCS16_POLYNOMIAL_REVERSED
@store:
  sta pppDecoderFcs
  dex
  bne @bit

  m8
  rts
.endproc

.proc pppFinishAtFlag
  .a8
  .i16

  lda pppDecoderFlags
  bit #PPP_DECODER_FLAG_SYNCHRONIZED
  bne @synchronized

  ora #PPP_DECODER_FLAG_SYNCHRONIZED
  sta pppDecoderFlags
  jsr pppPrepareNextFrame
  rts

@synchronized:
  bit #PPP_DECODER_FLAG_ESCAPED
  beq @checkOverflow
  lda #PPP_INVALID_ESCAPE_BEFORE_FLAG
  sta pppLastInvalidReason
  lda #PPP_EVENT_INVALID
  sta pppLastEvent
  jsr pppPrepareNextFrame
  rts

@checkOverflow:
  bit #PPP_DECODER_FLAG_OVERFLOWED
  beq @checkEmpty
  lda #PPP_EVENT_OVERFLOW
  sta pppLastEvent
  jsr pppPrepareNextFrame
  rts

@checkEmpty:
  lda pppDecoderLength
  ora pppDecoderLength + 1
  bne @checkLength
  rts

@checkLength:
  m16
  lda pppDecoderLength
  cmp #PPP_MINIMUM_FRAME_WITH_FCS_LENGTH
  bcs @checkFcs

  m8
  lda #PPP_INVALID_TOO_SHORT
  sta pppLastInvalidReason
  lda #PPP_EVENT_INVALID
  sta pppLastEvent
  jsr pppPrepareNextFrame
  rts

@checkFcs:
  .a16
  lda pppDecoderFcs
  cmp #PPP_GOOD_FCS16
  beq @frameComplete

  m8
  lda #PPP_EVENT_FCS_ERROR
  sta pppLastEvent
  jsr pppPrepareNextFrame
  rts

@frameComplete:
  .a16
  lda pppDecoderLength
  sec
  sbc #PPP_FCS16_LENGTH
  sta pppLastFrameLength

  ; Protocol extraction currently describes the uncompressed header form.
  ; A compressed header remains available in the frame buffer but reports
  ; protocol $0000 until compression support is implemented.
  m8
  stz pppLastProtocol
  stz pppLastProtocol + 1
  lda pppFrameBuffer
  cmp #$ff
  bne @reportFrame
  lda pppFrameBuffer + 1
  cmp #$03
  bne @reportFrame
  lda pppFrameBuffer + 2
  sta pppLastProtocol + 1
  lda pppFrameBuffer + 3
  sta pppLastProtocol

@reportFrame:
  lda #PPP_EVENT_FRAME
  sta pppLastEvent
  jsr pppPrepareNextFrame
  rts
.endproc

; Prepare to receive the octets following a Flag while retaining the
; synchronized bit and the completed frame bytes for the consumer.
.proc pppPrepareNextFrame
  .a8
  .i16

  lda pppDecoderFlags
  and #PPP_DECODER_FLAG_SYNCHRONIZED
  sta pppDecoderFlags
  stz pppDecoderLength
  stz pppDecoderLength + 1
  m16
  lda #PPP_INITIAL_FCS16
  sta pppDecoderFcs
  m8
  rts
.endproc
