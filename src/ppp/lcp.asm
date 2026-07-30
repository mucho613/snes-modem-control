.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppSnapshotBegin, pppSnapshotEnd
.import pppLastProtocol, pppLastFrameLength, pppFrameBuffer
.import pppLcpState, pppLcpLastCode, pppLcpLastIdentifier
.import pppLcpLastError, pppLcpRequestIdentifier, pppLcpRestartRemaining
.import pppLcpPeerFlags, pppLcpPendingAction, pppLcpPacketLength
.import pppLcpPeerMru, pppLcpPeerAccm, pppLcpReceiveCount
.import pppLcpPacketEnd, pppLcpOptionLength
.import pppLcpPeerMagic, pppLcpRestartDeadline, pppLcpTimerActive
.import pppLcpDeferredRequest, pppLcpPollAction
.import pppLcpTerminateRequestCount, pppLcpTerminateAckCount
.import pppLcpProtocolRejectCount, pppLcpLastRejectedProtocol
.import pppLcpRejectIdentifier

.export pppLcpInitialize, pppLcpParseFrame, pppLcpRunSelfTest

; Initialize the permanent LCP parser/negotiation state. The negotiation fields
; are reserved now so the packet parser and the next state-machine milestone
; share one stable diagnostic ABI.
.proc pppLcpInitialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppLcpState
  stz pppLcpLastCode
  stz pppLcpLastIdentifier
  stz pppLcpLastError
  stz pppLcpRequestIdentifier
  stz pppLcpRestartRemaining
  stz pppLcpPeerFlags
  stz pppLcpPendingAction
  stz pppLcpPacketLength
  stz pppLcpPacketLength + 1
  stz pppLcpRestartDeadline
  stz pppLcpRestartDeadline + 1
  stz pppLcpTimerActive
  stz pppLcpDeferredRequest
  stz pppLcpPollAction
  rep #$20
  .a16
  lda #PPP_DEFAULT_MRU
  sta pppLcpPeerMru
  lda #$ffff
  sta pppLcpPeerAccm
  sta pppLcpPeerAccm + 2
  stz pppLcpPeerMagic
  stz pppLcpPeerMagic + 2
  stz pppLcpReceiveCount
  stz pppLcpReceiveCount + 2
  stz pppLcpTerminateRequestCount
  stz pppLcpTerminateRequestCount + 2
  stz pppLcpTerminateAckCount
  stz pppLcpTerminateAckCount + 2
  stz pppLcpProtocolRejectCount
  stz pppLcpProtocolRejectCount + 2
  stz pppLcpLastRejectedProtocol
  sep #$20
  .a8
  stz pppLcpRejectIdentifier
  plb
  rts
.endproc

; Parse the FCS-verified uncompressed frame retained in pppFrameBuffer.
;
; Input:
;   pppLastProtocol and pppLastFrameLength describe pppFrameBuffer.
; Output:
;   Carry clear, A=PPP_LCP_ERROR_NONE: valid packet
;   Carry set,   A=PPP_LCP_ERROR_*: malformed or non-LCP packet
; Preserves:
;   X, Y, DBR
;
; The packet Length is network byte order and may be shorter than the PPP
; Information field; trailing padding remains ignored as required by RFC 1661.
; Configure packet options are validated without copying them.
.proc pppLcpParseFrame
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppSnapshotBegin
  pppIncrement32 pppLcpReceiveCount
  stz pppLcpLastCode
  stz pppLcpLastIdentifier
  stz pppLcpPacketLength
  stz pppLcpPacketLength + 1

  rep #$20
  .a16
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_LCP
  beq @checkHeader
  sep #$20
  .a8
  lda #PPP_LCP_ERROR_WRONG_PROTOCOL
  jmp @fail

@checkHeader:
  .a16
  lda pppLastFrameLength
  cmp #PPP_LCP_MINIMUM_FRAME_LENGTH
  bcs @readHeader
  sep #$20
  .a8
  lda #PPP_LCP_ERROR_TRUNCATED_HEADER
  jmp @fail

@readHeader:
  .a16
  sep #$20
  .a8
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET
  sta pppLcpLastCode
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + 1
  sta pppLcpLastIdentifier
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + 3
  sta pppLcpPacketLength
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + 2
  sta pppLcpPacketLength + 1

  rep #$20
  .a16
  lda pppLcpPacketLength
  cmp #PPP_LCP_HEADER_LENGTH
  bcs @checkAvailable
  sep #$20
  .a8
  lda #PPP_LCP_ERROR_INVALID_PACKET_LENGTH
  jmp @fail

@checkAvailable:
  .a16
  clc
  adc #PPP_LCP_FRAME_OFFSET
  sta pppLcpPacketEnd
  cmp pppLastFrameLength
  bcc @checkConfigure
  beq @checkConfigure
  sep #$20
  .a8
  lda #PPP_LCP_ERROR_TRUNCATED_PACKET
  jmp @fail

@checkConfigure:
  .a16
  sep #$20
  .a8
  lda pppLcpLastCode
  cmp #PPP_LCP_CODE_CONFIGURE_REQUEST
  bcc @success
  cmp #PPP_LCP_CODE_CONFIGURE_REJECT + 1
  bcs @success

  ; X is an absolute pppFrameBuffer offset. pppLcpPacketEnd points one byte
  ; beyond the Length-delimited LCP packet and excludes any PPP padding.
  rep #$20
  .a16
  ldx #PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH
@optionLoop:
  .a16
  cpx pppLcpPacketEnd
  beq @success16
  txa
  clc
  adc #$0002
  cmp pppLcpPacketEnd
  bcc @readOptionLength
  beq @readOptionLength
  sep #$20
  .a8
  lda #PPP_LCP_ERROR_TRUNCATED_OPTION
  jmp @fail

@readOptionLength:
  .a16
  sep #$20
  .a8
  lda pppFrameBuffer + 1, x
  cmp #$02
  bcs @checkOptionEnd
  lda #PPP_LCP_ERROR_INVALID_OPTION_LENGTH
  jmp @fail

@checkOptionEnd:
  .a8
  rep #$20
  .a16
  and #$00ff
  sta pppLcpOptionLength
  txa
  clc
  adc pppLcpOptionLength
  cmp pppLcpPacketEnd
  bcc @advanceOption
  beq @advanceOption
  sep #$20
  .a8
  lda #PPP_LCP_ERROR_OPTION_OVERRUN
  jmp @fail

@advanceOption:
  .a16
  tax
  bra @optionLoop

@success16:
  .a16
  sep #$20
  .a8
@success:
  stz pppLcpLastError
  jsr pppSnapshotEnd
  ply
  plx
  plb
  lda #PPP_LCP_ERROR_NONE
  clc
  rts

@fail:
  sta pppLcpLastError
  jsr pppSnapshotEnd
  ply
  plx
  plb
  sec
  rts
.endproc

; Permanent parser fixtures used through the existing PPP mailbox self-test.
;
; Output:
;   Carry clear, A=$00: passed
;   Carry set, A=$20-$27: failed step
.proc pppLcpRunSelfTest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppLcpInitialize

  ; Configure-Request id $42, MRU 1500, plus two ignored padding bytes.
  lda #$ff
  sta pppFrameBuffer + 0
  lda #$03
  sta pppFrameBuffer + 1
  lda #$c0
  sta pppFrameBuffer + 2
  lda #$21
  sta pppFrameBuffer + 3
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  sta pppFrameBuffer + 4
  lda #$42
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #$08
  sta pppFrameBuffer + 7
  lda #$01
  sta pppFrameBuffer + 8
  lda #$04
  sta pppFrameBuffer + 9
  lda #$05
  sta pppFrameBuffer + 10
  lda #$dc
  sta pppFrameBuffer + 11
  lda #$aa
  sta pppFrameBuffer + 12
  lda #$55
  sta pppFrameBuffer + 13
  rep #$20
  .a16
  lda #PPP_PROTOCOL_LCP
  sta pppLastProtocol
  lda #$000e
  sta pppLastFrameLength
  sep #$20
  .a8
  jsr pppLcpParseFrame
  bcc :+
  lda #$20
  jmp @fail
:
  lda pppLcpLastCode
  cmp #PPP_LCP_CODE_CONFIGURE_REQUEST
  beq :+
  jmp @fail21
:
  lda pppLcpLastIdentifier
  cmp #$42
  beq :+
  jmp @fail21
:
  rep #$20
  .a16
  lda pppLcpPacketLength
  cmp #$0008
  beq :+
  jmp @fail21_16
:
  sep #$20
  .a8

  ; Length below the four-byte LCP header.
  stz pppFrameBuffer + 6
  lda #$03
  sta pppFrameBuffer + 7
  jsr pppLcpParseFrame
  bcc @fail22
  cmp #PPP_LCP_ERROR_INVALID_PACKET_LENGTH
  bne @fail22

  ; Option Length one is structurally invalid.
  stz pppFrameBuffer + 6
  lda #$06
  sta pppFrameBuffer + 7
  lda #$01
  sta pppFrameBuffer + 8
  sta pppFrameBuffer + 9
  rep #$20
  .a16
  lda #$000a
  sta pppLastFrameLength
  sep #$20
  .a8
  jsr pppLcpParseFrame
  bcc @fail23
  cmp #PPP_LCP_ERROR_INVALID_OPTION_LENGTH
  bne @fail23

  ; Option claims four bytes while only its type and length remain.
  lda #$04
  sta pppFrameBuffer + 9
  jsr pppLcpParseFrame
  bcc @fail24
  cmp #PPP_LCP_ERROR_OPTION_OVERRUN
  bne @fail24

  ; Packet Length may not exceed the retained Information field.
  stz pppFrameBuffer + 6
  lda #$0a
  sta pppFrameBuffer + 7
  jsr pppLcpParseFrame
  bcc @fail25
  cmp #PPP_LCP_ERROR_TRUNCATED_PACKET
  bne @fail25

  ; A non-LCP frame is rejected before its packet header is inspected.
  rep #$20
  .a16
  lda #$0021
  sta pppLastProtocol
  sep #$20
  .a8
  jsr pppLcpParseFrame
  bcc @fail26
  cmp #PPP_LCP_ERROR_WRONG_PROTOCOL
  bne @fail26

  rep #$20
  .a16
  lda pppLcpReceiveCount
  cmp #$0006
  bne @fail27_16
  lda pppLcpReceiveCount + 2
  bne @fail27_16
  sep #$20
  .a8
  jsr pppLcpInitialize
  lda #$00
  clc
  bra @return

@fail21_16:
  sep #$20
  .a8
@fail21:
  lda #$21
  bra @fail
@fail22:
  lda #$22
  bra @fail
@fail23:
  lda #$23
  bra @fail
@fail24:
  lda #$24
  bra @fail
@fail25:
  lda #$25
  bra @fail
@fail26:
  lda #$26
  bra @fail
@fail27_16:
  sep #$20
  .a8
  lda #$27

@fail:
  pha
  jsr pppLcpInitialize
  pla
  sec

@return:
  ply
  plx
  plb
  rts
.endproc
