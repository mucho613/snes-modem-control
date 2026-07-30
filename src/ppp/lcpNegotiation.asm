.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppSnapshotBegin, pppSnapshotEnd
.import pppLcpParseFrame, pppLcpInitialize
.import pppLcpEvaluatePeerRequest, pppLcpBuildPeerResponse
.import pppLcpState, pppLcpLastIdentifier, pppLcpLastError
.import pppLcpRequestIdentifier, pppLcpRestartRemaining
.import pppLcpPendingAction, pppLcpPacketLength
.import pppLcpTimerActive, pppLcpDeferredRequest
.import pppLcpTerminateRequestCount, pppLcpTerminateAckCount
.import pppLcpProtocolRejectCount, pppLcpLastRejectedProtocol
.import pppLcpRejectIdentifier, pppLcpPeerMru
.import pppLcpPacketEnd, pppLcpOutputCursor
.import pppFrameBuffer, pppTransmitBuffer, pppTransmitActive
.import pppTransmitBegin, pppTransmitInitialize
.import pppLcpArmRestartTimer
.import pppLastProtocol, pppLastFrameLength

.export pppLcpOpen, pppLcpReceiveFrame, pppLcpRejectProtocol
.export pppLcpBuildPending
.export pppLcpNegotiationRunSelfTest

; Start LCP establishment with the conservative empty local option list.
; The pending request is built only after the shared PPP encoder is idle.
.proc pppLcpOpen
  .a8
  .i16

  phb
  setDBR $7e
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  beq @return
  jsr pppSnapshotBegin
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
  stz pppLcpRequestIdentifier
  lda #(PPP_LCP_DEFAULT_MAX_CONFIGURE - 1)
  sta pppLcpRestartRemaining
  stz pppLcpDeferredRequest
  lda #PPP_LCP_ACTION_CONFIGURE_REQUEST
  sta pppLcpPendingAction
  stz pppLcpLastError
  jsr pppSnapshotEnd
@return:
  .a8
  plb
  rts
.endproc

; Consume the parsed frame retained by the receive owner and update the
; RFC 1661 establishment state. This core deliberately leaves frame release
; and timer scheduling to the next main-loop integration layer.
;
; Output:
;   Carry clear: packet was structurally valid (possibly ignored)
;   Carry set: parser or Configure-response validation failed
.proc pppLcpReceiveFrame
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppSnapshotBegin
  jsr pppLcpParseFrame
  bcc @parsed
  jmp @returnFailure

@parsed:
  .a8
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSED
  beq @notConfiguring
  cmp #PPP_LCP_STATE_STOPPED
  beq @notConfiguring

  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET
  cmp #PPP_LCP_CODE_CONFIGURE_REQUEST
  beq @configureRequest
  cmp #PPP_LCP_CODE_CONFIGURE_ACK
  bne :+
  jmp @configureAck
:
  cmp #PPP_LCP_CODE_CONFIGURE_NAK
  bne :+
  jmp @configureNegative
:
  cmp #PPP_LCP_CODE_CONFIGURE_REJECT
  bne :+
  jmp @configureNegative
:
  cmp #PPP_LCP_CODE_TERMINATE_REQUEST
  beq @terminateRequest
  cmp #PPP_LCP_CODE_TERMINATE_ACK
  bne :+
  jmp @returnSuccess
:

  ; Maintenance and unknown Code processing remain outside this milestone.
  jmp @returnSuccess

@terminateRequest:
  .a8
  rep #$20
  .a16
  inc pppLcpTerminateRequestCount
  bne :+
  inc pppLcpTerminateRequestCount + 2
:
  sep #$20
  .a8
  stz pppLcpRestartRemaining
  stz pppLcpTimerActive
  stz pppLcpDeferredRequest
  lda #PPP_LCP_ACTION_TERMINATE_ACK
  sta pppLcpPendingAction
  jmp @returnSuccess

@notConfiguring:
  .a8
  lda #PPP_LCP_ERROR_NOT_CONFIGURING
  sta pppLcpLastError
  jmp @returnFailure

@configureRequest:
  .a8
  jsr pppLcpEvaluatePeerRequest
  sta pppLcpPendingAction
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  beq @openedPeerRequest
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  beq @acceptableRequest
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_RECEIVED
  bne :+
  jmp @returnSuccess
:
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
  jmp @returnSuccess

@openedPeerRequest:
  .a8
  inc pppLcpRequestIdentifier
  lda #(PPP_LCP_DEFAULT_MAX_CONFIGURE - 1)
  sta pppLcpRestartRemaining
  stz pppLcpTimerActive
  lda #$01
  sta pppLcpDeferredRequest
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  beq :+
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
  jmp @returnSuccess
:
  lda #PPP_LCP_STATE_ACK_SENT
  sta pppLcpState
  jmp @returnSuccess

@acceptableRequest:
  .a8
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_RECEIVED
  beq @requestCompletesOpen
  lda #PPP_LCP_STATE_ACK_SENT
  sta pppLcpState
  jmp @returnSuccess

@requestCompletesOpen:
  .a8
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  stz pppLcpRestartRemaining
  stz pppLcpTimerActive
  jmp @returnSuccess

@configureAck:
  .a8
  lda pppLcpLastIdentifier
  cmp pppLcpRequestIdentifier
  bne @invalidResponse
  rep #$20
  .a16
  lda pppLcpPacketLength
  cmp #PPP_LCP_HEADER_LENGTH
  bne @invalidResponse16

  sep #$20
  .a8
  lda pppLcpState
  cmp #PPP_LCP_STATE_REQUEST_SENT
  beq @ackReceived
  cmp #PPP_LCP_STATE_ACK_SENT
  beq @ackCompletesOpen
  cmp #PPP_LCP_STATE_ACK_RECEIVED
  beq @restartAfterDuplicateAck
  cmp #PPP_LCP_STATE_OPENED
  beq @restartAfterDuplicateAck
  bra @returnSuccess

@ackReceived:
  .a8
  lda #PPP_LCP_STATE_ACK_RECEIVED
  sta pppLcpState
  lda #PPP_LCP_DEFAULT_MAX_CONFIGURE
  sta pppLcpRestartRemaining
  bra @returnSuccess

@ackCompletesOpen:
  .a8
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  stz pppLcpRestartRemaining
  stz pppLcpTimerActive
  bra @returnSuccess

@restartAfterDuplicateAck:
  .a8
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
  jsr @newRequest
  bra @returnSuccess

@configureNegative:
  .a8
  lda pppLcpLastIdentifier
  cmp pppLcpRequestIdentifier
  bne @invalidResponse
  rep #$20
  .a16
  lda pppLcpPacketLength
  cmp #PPP_LCP_HEADER_LENGTH
  bne @invalidResponse16

  sep #$20
  .a8
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_SENT
  beq @negativeKeepsAckSent
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
  bra @negativeNewRequest

@negativeKeepsAckSent:
  .a8
  lda #PPP_LCP_STATE_ACK_SENT
  sta pppLcpState
@negativeNewRequest:
  .a8
  jsr @newRequest
  bra @returnSuccess

@invalidResponse16:
  .a16
  sep #$20
  .a8
@invalidResponse:
  .a8
  lda #PPP_LCP_ERROR_INVALID_RESPONSE
  sta pppLcpLastError
  jmp @returnFailure

@returnSuccess:
  .a8
  stz pppLcpLastError
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

@returnFailure:
  .a8
  jsr pppSnapshotEnd
  ply
  plx
  plb
  sec
  rts

; Allocate a fresh Identifier only when the request contents or a valid
; response require a new Configure-Request. Timeout retransmission will keep
; the current Identifier in the next milestone.
@newRequest:
  .a8
  inc pppLcpRequestIdentifier
  lda #(PPP_LCP_DEFAULT_MAX_CONFIGURE - 1)
  sta pppLcpRestartRemaining
  stz pppLcpTimerActive
  stz pppLcpDeferredRequest
  lda #PPP_LCP_ACTION_CONFIGURE_REQUEST
  sta pppLcpPendingAction
  rts
.endproc

; Queue a Protocol-Reject for the retained unknown PPP frame. The caller owns
; pppFrameBuffer until pppLcpBuildPending enters the shared transmitter.
.proc pppLcpRejectProtocol
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  rep #$20
  .a16
  lda pppLastProtocol
  sta pppLcpLastRejectedProtocol
  sep #$20
  .a8
  inc pppLcpRejectIdentifier
  lda #PPP_LCP_ACTION_PROTOCOL_REJECT
  sta pppLcpPendingAction
  jsr pppSnapshotEnd
  plb
  rts
.endproc

; Build the current pending LCP packet directly into the shared PPP transmit
; buffer and start its restartable RFC 1662 encoder.
;
; Output carry clear when a packet was accepted by the encoder. Carry set
; means there was no pending packet or the encoder was still busy.
.proc pppLcpBuildPending
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  lda pppLcpPendingAction
  bne :+
  jmp @busy
:
  lda pppTransmitActive
  beq :+
  jmp @busy
:

  lda #$ff
  sta pppTransmitBuffer + 0
  lda #$03
  sta pppTransmitBuffer + 1
  lda #$c0
  sta pppTransmitBuffer + 2
  lda #$21
  sta pppTransmitBuffer + 3

  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_REQUEST
  beq @buildRequest
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  beq @copyResponse
  cmp #PPP_LCP_ACTION_CONFIGURE_NAK
  beq @buildSelectiveResponse
  cmp #PPP_LCP_ACTION_CONFIGURE_REJECT
  beq @buildSelectiveResponse
  cmp #PPP_LCP_ACTION_TERMINATE_ACK
  beq @buildTerminateAck
  cmp #PPP_LCP_ACTION_PROTOCOL_REJECT
  beq @buildProtocolReject
  jmp @busy

@buildRequest:
  .a8
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  sta pppTransmitBuffer + 4
  lda pppLcpRequestIdentifier
  sta pppTransmitBuffer + 5
  stz pppTransmitBuffer + 6
  lda #PPP_LCP_HEADER_LENGTH
  sta pppTransmitBuffer + 7
  rep #$20
  .a16
  lda #PPP_LCP_MINIMUM_FRAME_LENGTH
  jmp @begin

@copyResponse:
  .a8
  rep #$20
  .a16
  ldx #$0000
@copyLoop:
  .a16
  cpx pppLcpPacketLength
  beq @selectResponseCode
  sep #$20
  .a8
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET, x
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET, x
  rep #$20
  .a16
  inx
  bra @copyLoop

@selectResponseCode:
  .a16
  sep #$20
  .a8
  lda #PPP_LCP_CODE_CONFIGURE_ACK
  .a8
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET
  rep #$20
  .a16
  lda pppLcpPacketLength
  clc
  adc #PPP_UNCOMPRESSED_HEADER_LENGTH
  jmp @begin

@buildSelectiveResponse:
  .a8
  jsr pppLcpBuildPeerResponse
  jmp @begin

@buildTerminateAck:
  .a8
  lda #PPP_LCP_CODE_TERMINATE_ACK
  sta pppTransmitBuffer + 4
  lda pppLcpLastIdentifier
  sta pppTransmitBuffer + 5
  stz pppTransmitBuffer + 6
  lda #PPP_LCP_HEADER_LENGTH
  sta pppTransmitBuffer + 7
  rep #$20
  .a16
  lda #PPP_LCP_MINIMUM_FRAME_LENGTH
  jmp @begin

@buildProtocolReject:
  .a8
  lda #PPP_LCP_CODE_PROTOCOL_REJECT
  sta pppTransmitBuffer + 4
  lda pppLcpRejectIdentifier
  sta pppTransmitBuffer + 5

  ; LCP Length includes its four-byte header. Limit it to the received frame,
  ; the peer MRU, and this build's fixed 1500-byte transmit Information area.
  rep #$20
  .a16
  lda pppLastFrameLength
  clc
  adc #$0002
  cmp pppLcpPeerMru
  bcc :+
  beq :+
  lda pppLcpPeerMru
:
  cmp #PPP_DEFAULT_MRU + 1
  bcc :+
  lda #PPP_DEFAULT_MRU
:
  cmp #$0006
  bcs :+
  lda #$0006
:
  sta pppLcpOutputCursor
  xba
  sep #$20
  .a8
  sta pppTransmitBuffer + 6
  lda pppLcpOutputCursor
  sta pppTransmitBuffer + 7

  rep #$20
  .a16
  lda pppLcpOutputCursor
  sec
  sbc #PPP_LCP_HEADER_LENGTH
  sta pppLcpPacketEnd
  ldx #PPP_UNCOMPRESSED_HEADER_LENGTH - 2
  ldy #PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_LCP_HEADER_LENGTH
@copyRejectedFrame:
  .a16
  lda pppLcpPacketEnd
  beq @protocolRejectLength
  sep #$20
  .a8
  lda pppFrameBuffer, x
  sta pppTransmitBuffer, y
  rep #$20
  .a16
  inx
  iny
  dec pppLcpPacketEnd
  bra @copyRejectedFrame

@protocolRejectLength:
  .a16
  lda pppLcpOutputCursor
  clc
  adc #PPP_UNCOMPRESSED_HEADER_LENGTH

@begin:
  .a16
  jsr pppTransmitBegin
  bcs @busy16
  sep #$20
  .a8
  jsr pppSnapshotBegin
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_REQUEST
  bne @maybeTerminateAck
  jsr pppLcpArmRestartTimer
  bra :+
@maybeTerminateAck:
  cmp #PPP_LCP_ACTION_TERMINATE_ACK
  bne @maybeProtocolReject
  rep #$20
  .a16
  inc pppLcpTerminateAckCount
  bne :+
  inc pppLcpTerminateAckCount + 2
:
  sep #$20
  .a8
  bra @counterDone
@maybeProtocolReject:
  cmp #PPP_LCP_ACTION_PROTOCOL_REJECT
  bne @counterDone
  rep #$20
  .a16
  inc pppLcpProtocolRejectCount
  bne :+
  inc pppLcpProtocolRejectCount + 2
:
  sep #$20
  .a8
@counterDone:
  stz pppLcpPendingAction
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

@busy16:
  .a16
  sep #$20
  .a8
@busy:
  .a8
  ply
  plx
  plb
  sec
  rts
.endproc

; Fixed transcript for the 65816 Configure core. The frame fixtures are
; unescaped, FCS-verified frames exactly as retained by the receive decoder.
;
; Output:
;   Carry clear, A=$00: passed
;   Carry set, A=$30-$3f: failed step
.proc pppLcpNegotiationRunSelfTest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  jsr pppLcpOpen

  lda pppLcpState
  cmp #PPP_LCP_STATE_REQUEST_SENT
  beq :+
  jmp @fail30
:
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_REQUEST
  beq :+
  jmp @fail30
:
  jsr pppLcpBuildPending
  bcc :+
  jmp @fail31
:
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CONFIGURE_REQUEST
  beq :+
  jmp @fail31
:
  lda pppTransmitBuffer + 5
  beq :+
  jmp @fail31
:
  lda pppTransmitBuffer + 7
  cmp #PPP_LCP_HEADER_LENGTH
  beq :+
  jmp @fail31
:

  ; Let the transcript inject a peer packet without polling wire output.
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  ldx #$0007
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  bcc :+
  jmp @fail32
:
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_SENT
  beq :+
  jmp @fail32
:
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  beq :+
  jmp @fail32
:
  jsr pppLcpBuildPending
  bcc :+
  jmp @fail33
:
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CONFIGURE_ACK
  beq :+
  jmp @fail33
:
  lda pppTransmitBuffer + 5
  cmp #$07
  beq :+
  jmp @fail33
:

  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_CONFIGURE_ACK
  ldx #$0000
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  bcc :+
  jmp @fail34
:
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  beq :+
  jmp @fail34
:

  ; Reverse Ack ordering: our request is Acked before the peer request.
  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  jsr pppLcpOpen
  jsr pppLcpBuildPending
  bcc :+
  jmp @fail35
:
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_CONFIGURE_ACK
  ldx #$0000
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  bcc :+
  jmp @fail35
:
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_RECEIVED
  beq :+
  jmp @fail35
:
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  ldx #$0009
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  bcc :+
  jmp @fail36
:
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  beq :+
  jmp @fail36
:

  ; Wrong Identifier does not advance the state.
  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  jsr pppLcpOpen
  jsr pppLcpBuildPending
  bcc :+
  jmp @fail37
:
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_CONFIGURE_ACK
  ldx #$0042
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  bcs :+
  jmp @fail37
:
  lda pppLcpLastError
  cmp #PPP_LCP_ERROR_INVALID_RESPONSE
  beq :+
  jmp @fail37
:
  lda pppLcpState
  cmp #PPP_LCP_STATE_REQUEST_SENT
  beq :+
  jmp @fail37
:

  ; A valid empty Nak allocates a fresh request Identifier.
  lda #PPP_LCP_CODE_CONFIGURE_NAK
  ldx #$0000
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  bcc :+
  jmp @fail38
:
  lda pppLcpRequestIdentifier
  cmp #$01
  beq :+
  jmp @fail38
:
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_REQUEST
  beq :+
  jmp @fail38
:

  ; A supported non-empty request is Acked without changing its option bytes.
  jsr pppLcpBuildPending
  bcc :+
  jmp @fail39
:
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  ldx #$000a
  jsr @writeMruPacket
  jsr pppLcpReceiveFrame
  bcc :+
  jmp @fail39
:
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  beq :+
  jmp @fail39
:
  jsr pppLcpBuildPending
  bcc :+
  jmp @fail3a
:
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CONFIGURE_ACK
  bne @fail3a
  lda pppTransmitBuffer + 5
  cmp #$0a
  bne @fail3a
  lda pppTransmitBuffer + 8
  cmp #$01
  bne @fail3a
  lda pppTransmitBuffer + 9
  cmp #$04
  bne @fail3a

  ; Peer termination uses the peer Identifier and an empty Ack payload.
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_TERMINATE_REQUEST
  ldx #$0042
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  bcs @fail3b
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_TERMINATE_ACK
  bne @fail3b
  jsr pppLcpBuildPending
  bcs @fail3b
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_TERMINATE_ACK
  bne @fail3b
  lda pppTransmitBuffer + 5
  cmp #$42
  bne @fail3b
  lda pppTransmitBuffer + 7
  cmp #PPP_LCP_HEADER_LENGTH
  bne @fail3b

  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  lda #$00
  clc
  bra @return

@fail30:
  lda #$30
  bra @fail
@fail31:
  lda #$31
  bra @fail
@fail32:
  lda #$32
  bra @fail
@fail33:
  lda #$33
  bra @fail
@fail34:
  lda #$34
  bra @fail
@fail35:
  lda #$35
  bra @fail
@fail36:
  lda #$36
  bra @fail
@fail37:
  lda #$37
  bra @fail
@fail38:
  lda #$38
  bra @fail
@fail39:
  lda #$39
  bra @fail
@fail3a:
  lda #$3a
  bra @fail
@fail3b:
  lda #$3b

@fail:
  pha
  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  pla
  sec

@return:
  ply
  plx
  plb
  rts

; Input A=Code, X low byte=Identifier.
@writeEmptyPacket:
  .a8
  sta pppFrameBuffer + 4
  txa
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #PPP_LCP_HEADER_LENGTH
  sta pppFrameBuffer + 7
  rep #$20
  .a16
  lda #PPP_PROTOCOL_LCP
  sta pppLastProtocol
  lda #PPP_LCP_MINIMUM_FRAME_LENGTH
  sta pppLastFrameLength
  sep #$20
  .a8
  rts

; Input A=Code, X low byte=Identifier. Adds MRU 1500.
@writeMruPacket:
  .a8
  sta pppFrameBuffer + 4
  txa
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
  rep #$20
  .a16
  lda #PPP_PROTOCOL_LCP
  sta pppLastProtocol
  lda #$000c
  sta pppLastFrameLength
  sep #$20
  .a8
  rts
.endproc
