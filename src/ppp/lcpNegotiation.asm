.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppSnapshotBegin, pppSnapshotEnd
.import pppLcpParseFrame, pppLcpInitialize
.import pppLcpEvaluatePeerRequest, pppLcpBuildPeerResponse
.import pppLcpPeerMagicMatchesLocal
.import pppLcpState, pppLcpLastCode, pppLcpLastIdentifier, pppLcpLastError
.import pppLcpRequestIdentifier, pppLcpRestartRemaining
.import pppLcpPendingAction, pppLcpPacketLength
.import pppLcpTimerActive, pppLcpDeferredRequest
.import pppLcpAdministrativeOpen
.import pppLcpLocalTerminateRequestCount, pppLcpLocalTerminateAckCount
.import pppLcpTerminateRequestCount, pppLcpTerminateAckCount
.import pppLcpProtocolRejectCount, pppLcpLastRejectedProtocol
.import pppLcpRejectIdentifier, pppLcpPeerFlags, pppLcpPeerMru
.import pppLcpPeerMagic
.import pppLcpLocalMagic, pppLcpLocalFlags, pppLcpLoopbackCount
.import pppLcpCodeRejectCount, pppLcpLastRejectedCode
.import pppLcpEchoRequestCount, pppLcpEchoReplyCount, pppLcpEchoDropCount
.import pppLcpLastEchoIdentifier, pppLcpLastEchoMagic
.import pppLcpPacketEnd, pppLcpOutputCursor, pppLcpOptionLength
.import pppLcpHasNak
.import pppFrameBuffer, pppTransmitBuffer, pppTransmitActive
.import pppTransmitBegin, pppTransmitInitialize
.import pppLcpArmRestartTimer, pppLcpLocalTerminateComplete
.import pppLastProtocol, pppLastFrameLength
.import frameCounter

.export pppLcpOpen, pppLcpClose, pppLcpReceiveFrame, pppLcpRejectProtocol
.export pppLcpRejectCode
.export pppLcpBuildPending, pppLcpAdvanceLocalMagic
.export pppLcpWriteLocalAckTestPacket
.export pppLcpNegotiationRunSelfTest

.macro pppLcpNegotiationRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

.macro pppLcpNegotiationRequireNonzero failure
  bne :+
  jmp failure
:
.endmacro

.macro pppLcpNegotiationRequireCarryClear failure
  bcc :+
  jmp failure
:
.endmacro

; Start LCP establishment with a locally generated Magic-Number option.
; The pending request is built only after the shared PPP encoder is idle.
.proc pppLcpOpen
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  lda #$01
  sta pppLcpAdministrativeOpen
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  beq @finish
  cmp #PPP_LCP_STATE_CLOSING
  beq @finish
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
  m16
  lda frameCounter
  eor #$4d24
  sta pppLcpLocalMagic
  lda frameCounter + 2
  eor #$4e44
  sta pppLcpLocalMagic + 2
  ora pppLcpLocalMagic
  bne :+
  inc pppLcpLocalMagic
:
  m8
  lda #PPP_LCP_LOCAL_FLAG_MAGIC_REQUEST
  sta pppLcpLocalFlags
  stz pppLcpRequestIdentifier
  lda #(PPP_LCP_DEFAULT_MAX_CONFIGURE - 1)
  sta pppLcpRestartRemaining
  stz pppLcpDeferredRequest
  lda #PPP_LCP_ACTION_CONFIGURE_REQUEST
  sta pppLcpPendingAction
  stz pppLcpLastError
@finish:
  jsr pppSnapshotEnd
  assert_m8_i16
  plb
  rts
.endproc

; Request an administrative LCP close. If a response packet already owns the
; one-entry pending slot, pppLcpPoll starts Closing as soon as that packet has
; entered the shared transmitter.
.proc pppLcpClose
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  stz pppLcpAdministrativeOpen

  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSED
  beq @alreadyClosed
  cmp #PPP_LCP_STATE_STOPPED
  beq @alreadyClosed
  cmp #PPP_LCP_STATE_CLOSING
  beq @finish
  lda pppLcpPendingAction
  bne @finish

  lda #PPP_LCP_STATE_CLOSING
  sta pppLcpState
  inc pppLcpRequestIdentifier
  lda #(PPP_LCP_DEFAULT_MAX_TERMINATE - 1)
  sta pppLcpRestartRemaining
  stz pppLcpTimerActive
  stz pppLcpDeferredRequest
  lda #PPP_LCP_ACTION_TERMINATE_REQUEST
  sta pppLcpPendingAction
  stz pppLcpLastError
  bra @finish

@alreadyClosed:
  assert_m8_i16
  jsr pppLcpLocalTerminateComplete

@finish:
  assert_m8_i16
  jsr pppSnapshotEnd
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
  assert_m8_i16
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSED
  bne :+
  jmp @notConfiguring
:
  cmp #PPP_LCP_STATE_STOPPED
  bne :+
  jmp @notConfiguring
:

  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET
  cmp #PPP_LCP_CODE_CONFIGURE_REQUEST
  bne :+
  jmp @configureRequest
:
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
  bne :+
  jmp @terminateRequest
:
  cmp #PPP_LCP_CODE_TERMINATE_ACK
  bne :+
  jmp @terminateAck
:
  cmp #PPP_LCP_CODE_ECHO_REQUEST
  bne :+
  jmp @echoRequest
:
  cmp #PPP_LCP_CODE_ECHO_REPLY
  bne :+
  jmp @openedMaintenancePacket
:
  cmp #PPP_LCP_CODE_DISCARD_REQUEST
  bne :+
  jmp @openedMaintenancePacket
:

  ; Code-Reject and Protocol-Reject are known even though their receive-side
  ; consequences are not modeled yet. Only genuinely unknown values receive
  ; Code-Reject.
  cmp #PPP_LCP_CODE_CODE_REJECT
  bcs :+
  jmp @unknownCode
:
  cmp #PPP_LCP_CODE_PROTOCOL_REJECT + 1
  bcc :+
  jmp @unknownCode
:
  jmp @returnSuccess

@openedMaintenancePacket:
  assert_m8_i16
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  bne :+
  jmp @returnSuccess
:
  lda #PPP_LCP_ERROR_NOT_CONFIGURING
  sta pppLcpLastError
  jmp @returnFailure

@terminateAck:
  assert_m8_i16
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSING
  beq :+
  jmp @returnSuccess
:
  lda pppLcpLastIdentifier
  cmp pppLcpRequestIdentifier
  beq :+
  jmp @invalidResponse
:
  m16
  inc pppLcpLocalTerminateAckCount
  bne :+
  inc pppLcpLocalTerminateAckCount + 2
:
  m8
  jsr pppLcpLocalTerminateComplete
  jmp @returnSuccess

@echoRequest:
  assert_m8_i16
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  bne @echoWrongPhase

  m16
  lda pppLcpPacketLength
  cmp #(PPP_LCP_HEADER_LENGTH + 4)
  bcc @echoMalformed16
  m8

  lda pppLcpPeerFlags
  and #PPP_LCP_PEER_FLAG_MAGIC_NUMBER
  beq @echoExpectZeroMagic
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 0
  cmp pppLcpPeerMagic + 3
  bne @echoUnexpectedMagic
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 1
  cmp pppLcpPeerMagic + 2
  bne @echoUnexpectedMagic
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 2
  cmp pppLcpPeerMagic + 1
  bne @echoUnexpectedMagic
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 3
  cmp pppLcpPeerMagic + 0
  bne @echoUnexpectedMagic
  bra @acceptEcho

@echoExpectZeroMagic:
  assert_m8_i16
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 0
  ora pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 1
  ora pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 2
  ora pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 3
  bne @echoUnexpectedMagic

@acceptEcho:
  assert_m8_i16
  lda pppLcpLastIdentifier
  sta pppLcpLastEchoIdentifier
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 3
  sta pppLcpLastEchoMagic + 0
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 2
  sta pppLcpLastEchoMagic + 1
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 1
  sta pppLcpLastEchoMagic + 2
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 0
  sta pppLcpLastEchoMagic + 3
  m16
  inc pppLcpEchoRequestCount
  bne :+
  inc pppLcpEchoRequestCount + 2
:
  m8
  lda #PPP_LCP_ACTION_ECHO_REPLY
  sta pppLcpPendingAction
  jmp @returnSuccess

@echoMalformed16:
  assert_m16_i16
  m8
  lda #PPP_LCP_ERROR_MALFORMED_ECHO_REQUEST
  bra @dropEcho

@echoUnexpectedMagic:
  assert_m8_i16
  lda #PPP_LCP_ERROR_UNEXPECTED_MAGIC_NUMBER
  bra @dropEcho

@echoWrongPhase:
  assert_m8_i16
  lda #PPP_LCP_ERROR_NOT_CONFIGURING

@dropEcho:
  assert_m8_i16
  sta pppLcpLastError
  m16
  inc pppLcpEchoDropCount
  bne :+
  inc pppLcpEchoDropCount + 2
:
  m8
  jmp @returnFailure

@unknownCode:
  assert_m8_i16
  jsr pppLcpRejectCode
  jmp @returnSuccess

@terminateRequest:
  assert_m8_i16
  m16
  inc pppLcpTerminateRequestCount
  bne :+
  inc pppLcpTerminateRequestCount + 2
:
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSING
  beq @terminateRequestWhileClosing
  stz pppLcpRestartRemaining
  stz pppLcpTimerActive
  stz pppLcpDeferredRequest
@terminateRequestWhileClosing:
  assert_m8_i16
  lda #PPP_LCP_ACTION_TERMINATE_ACK
  sta pppLcpPendingAction
  jmp @returnSuccess

@notConfiguring:
  assert_m8_i16
  lda #PPP_LCP_ERROR_NOT_CONFIGURING
  sta pppLcpLastError
  jmp @returnFailure

@configureRequest:
  assert_m8_i16
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSING
  bne :+
  jmp @notConfiguring
:
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
  assert_m8_i16
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
  assert_m8_i16
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_RECEIVED
  beq @requestCompletesOpen
  lda #PPP_LCP_STATE_ACK_SENT
  sta pppLcpState
  jmp @returnSuccess

@requestCompletesOpen:
  assert_m8_i16
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  stz pppLcpRestartRemaining
  stz pppLcpTimerActive
  jmp @returnSuccess

@configureAck:
  assert_m8_i16
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSING
  bne :+
  jmp @notConfiguring
:
  lda pppLcpLastIdentifier
  cmp pppLcpRequestIdentifier
  beq :+
  jmp @invalidResponse
:
  lda pppLcpLocalFlags
  and #PPP_LCP_LOCAL_FLAG_MAGIC_REQUEST
  beq @ackExpectEmpty
  m16
  lda pppLcpPacketLength
  cmp #(PPP_LCP_HEADER_LENGTH + 6)
  beq :+
  jmp @invalidResponse16
:
  m8
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 0
  cmp #PPP_LCP_OPTION_MAGIC_NUMBER
  beq :+
  jmp @invalidResponse
:
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 1
  cmp #$06
  beq :+
  jmp @invalidResponse
:
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 2
  cmp pppLcpLocalMagic + 3
  beq :+
  jmp @invalidResponse
:
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 3
  cmp pppLcpLocalMagic + 2
  beq :+
  jmp @invalidResponse
:
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 4
  cmp pppLcpLocalMagic + 1
  beq :+
  jmp @invalidResponse
:
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 5
  cmp pppLcpLocalMagic + 0
  beq :+
  jmp @invalidResponse
:
  lda pppLcpLocalFlags
  ora #PPP_LCP_LOCAL_FLAG_MAGIC_ACKNOWLEDGED
  sta pppLcpLocalFlags
  bra @ackValidated

@ackExpectEmpty:
  assert_m8_i16
  m16
  lda pppLcpPacketLength
  cmp #PPP_LCP_HEADER_LENGTH
  bne @invalidResponse16
  m8
@ackValidated:
  assert_m8_i16

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
  assert_m8_i16
  lda #PPP_LCP_STATE_ACK_RECEIVED
  sta pppLcpState
  lda #PPP_LCP_DEFAULT_MAX_CONFIGURE
  sta pppLcpRestartRemaining
  bra @returnSuccess

@ackCompletesOpen:
  assert_m8_i16
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  stz pppLcpRestartRemaining
  stz pppLcpTimerActive
  bra @returnSuccess

@restartAfterDuplicateAck:
  assert_m8_i16
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
  jsr @newRequest
  bra @returnSuccess

@configureNegative:
  assert_m8_i16
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSING
  bne :+
  jmp @notConfiguring
:
  lda pppLcpLastIdentifier
  cmp pppLcpRequestIdentifier
  bne @invalidResponse
  jsr @applyNegativeOptions
  bcs @invalidResponse

  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_SENT
  beq @negativeKeepsAckSent
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
  bra @negativeNewRequest

@negativeKeepsAckSent:
  assert_m8_i16
  lda #PPP_LCP_STATE_ACK_SENT
  sta pppLcpState
@negativeNewRequest:
  assert_m8_i16
  jsr @newRequest
  bra @returnSuccess

@invalidResponse16:
  assert_m16_i16
  m8
@invalidResponse:
  assert_m8_i16
  lda #PPP_LCP_ERROR_INVALID_RESPONSE
  sta pppLcpLastError
  jmp @returnFailure

@returnSuccess:
  assert_m8_i16
  stz pppLcpLastError
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

@returnFailure:
  assert_m8_i16
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
  assert_m8_i16
  lda pppLcpLocalFlags
  and #($ff ^ PPP_LCP_LOCAL_FLAG_MAGIC_ACKNOWLEDGED)
  sta pppLcpLocalFlags
  inc pppLcpRequestIdentifier
  lda #(PPP_LCP_DEFAULT_MAX_CONFIGURE - 1)
  sta pppLcpRestartRemaining
  stz pppLcpTimerActive
  stz pppLcpDeferredRequest
  lda #PPP_LCP_ACTION_CONFIGURE_REQUEST
  sta pppLcpPendingAction
  rts

; Apply Magic-Number Configure-Nak/Reject content to the local request.
; Empty Nak remains accepted for compatibility with the earlier empty-option
; implementation. Reject must contain only exact requested option bytes.
@applyNegativeOptions:
  assert_m8_i16
  stz pppLcpHasNak
  ldy #PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH
@negativeOptionLoop:
  assert_m8_i16
  cpy pppLcpPacketEnd
  bne :+
  jmp @negativeOptionsDone
:
  lda pppFrameBuffer, y
  cmp #PPP_LCP_OPTION_MAGIC_NUMBER
  beq @negativeMagic
  lda pppLcpLastCode
  cmp #PPP_LCP_CODE_CONFIGURE_REJECT
  bne :+
  jmp @negativeInvalid
:
  bra @negativeAdvance

@negativeMagic:
  assert_m8_i16
  lda pppLcpHasNak
  beq :+
  jmp @negativeInvalid
:
  inc pppLcpHasNak
  lda pppLcpLocalFlags
  and #PPP_LCP_LOCAL_FLAG_MAGIC_REQUEST
  bne :+
  jmp @negativeInvalid
:
  lda pppFrameBuffer + 1, y
  cmp #$06
  beq :+
  jmp @negativeInvalid
:
  lda pppLcpLastCode
  cmp #PPP_LCP_CODE_CONFIGURE_REJECT
  bne @negativeMagicNak
  jsl pppLcpPeerMagicMatchesLocal
  beq :+
  jmp @negativeInvalid
:
  lda pppLcpLocalFlags
  and #($ff ^ (PPP_LCP_LOCAL_FLAG_MAGIC_REQUEST | PPP_LCP_LOCAL_FLAG_MAGIC_ACKNOWLEDGED))
  sta pppLcpLocalFlags
  m16
  stz pppLcpLocalMagic
  stz pppLcpLocalMagic + 2
  m8
  bra @negativeAdvance

@negativeMagicNak:
  assert_m8_i16
  lda pppFrameBuffer + 2, y
  ora pppFrameBuffer + 3, y
  ora pppFrameBuffer + 4, y
  ora pppFrameBuffer + 5, y
  beq @negativeAdvanceMagic
  jsl pppLcpPeerMagicMatchesLocal
  beq @negativeAdvanceMagic
  lda pppFrameBuffer + 5, y
  sta pppLcpLocalMagic + 0
  lda pppFrameBuffer + 4, y
  sta pppLcpLocalMagic + 1
  lda pppFrameBuffer + 3, y
  sta pppLcpLocalMagic + 2
  lda pppFrameBuffer + 2, y
  sta pppLcpLocalMagic + 3
  bra @negativeAdvance

@negativeAdvanceMagic:
  assert_m8_i16
  jsl pppLcpAdvanceLocalMagic

@negativeAdvance:
  assert_m8_i16
  lda pppFrameBuffer + 1, y
  sta pppLcpOptionLength
  stz pppLcpOptionLength + 1
  m16
  tya
  clc
  adc pppLcpOptionLength
  tay
  m8
  jmp @negativeOptionLoop

@negativeOptionsDone:
  assert_m8_i16
  lda pppLcpLastCode
  cmp #PPP_LCP_CODE_CONFIGURE_NAK
  beq @negativeValid
  lda pppLcpHasNak
  beq @negativeInvalid
@negativeValid:
  assert_m8_i16
  clc
  rts
@negativeInvalid:
  assert_m8_i16
  sec
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
  m16
  lda pppLastProtocol
  sta pppLcpLastRejectedProtocol
  m8
  inc pppLcpRejectIdentifier
  lda #PPP_LCP_ACTION_PROTOCOL_REJECT
  sta pppLcpPendingAction
  jsr pppSnapshotEnd
  plb
  rts
.endproc

; Queue a Code-Reject for the retained, parsed LCP packet. The caller owns
; pppFrameBuffer until pppLcpBuildPending enters the shared transmitter.
.proc pppLcpRejectCode
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  lda pppLcpLastCode
  sta pppLcpLastRejectedCode
  inc pppLcpRejectIdentifier
  lda #PPP_LCP_ACTION_CODE_REJECT
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
  bne :+
  jmp @buildRequest
:
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  bne :+
  jmp @copyResponse
:
  cmp #PPP_LCP_ACTION_CONFIGURE_NAK
  bne :+
  jmp @buildSelectiveResponse
:
  cmp #PPP_LCP_ACTION_CONFIGURE_REJECT
  bne :+
  jmp @buildSelectiveResponse
:
  cmp #PPP_LCP_ACTION_TERMINATE_ACK
  bne :+
  jmp @buildTerminateAck
:
  cmp #PPP_LCP_ACTION_PROTOCOL_REJECT
  bne :+
  jmp @buildProtocolReject
:
  cmp #PPP_LCP_ACTION_CODE_REJECT
  bne :+
  jmp @buildCodeReject
:
  cmp #PPP_LCP_ACTION_ECHO_REPLY
  bne :+
  jmp @buildEchoReply
:
  cmp #PPP_LCP_ACTION_TERMINATE_REQUEST
  bne :+
  jmp @buildTerminateRequest
:
  jmp @busy

@buildEchoReply:
  assert_m8_i16
  ; Bound the complete LCP Echo-Reply by the request Length, negotiated peer
  ; MRU, and fixed transmit Information area. The eight-byte Echo header is
  ; retained even if a broken peer advertised an unusably small MRU.
  m16
  lda pppLcpPacketLength
  cmp pppLcpPeerMru
  bcc :+
  beq :+
  lda pppLcpPeerMru
:
  cmp #PPP_DEFAULT_MRU + 1
  bcc :+
  lda #PPP_DEFAULT_MRU
:
  cmp #(PPP_LCP_HEADER_LENGTH + 4)
  bcs :+
  lda #(PPP_LCP_HEADER_LENGTH + 4)
:
  sta pppLcpOutputCursor
  ldx #$0000
@copyEchoPacket:
  assert_m16_i16
  cpx pppLcpOutputCursor
  beq @finishEchoPacket
  m8
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET, x
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET, x
  m16
  inx
  bra @copyEchoPacket

@finishEchoPacket:
  assert_m16_i16
  lda pppLcpOutputCursor
  xba
  m8
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + 2
  lda pppLcpOutputCursor
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + 3
  lda #PPP_LCP_CODE_ECHO_REPLY
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET
  lda pppLcpLocalFlags
  and #PPP_LCP_LOCAL_FLAG_MAGIC_ACKNOWLEDGED
  beq @echoZeroMagic
  lda pppLcpLocalMagic + 3
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 0
  lda pppLcpLocalMagic + 2
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 1
  lda pppLcpLocalMagic + 1
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 2
  lda pppLcpLocalMagic + 0
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 3
  bra @echoMagicDone
@echoZeroMagic:
  assert_m8_i16
  stz pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 0
  stz pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 1
  stz pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 2
  stz pppTransmitBuffer + PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH + 3
@echoMagicDone:
  assert_m8_i16
  m16
  lda pppLcpOutputCursor
  clc
  adc #PPP_UNCOMPRESSED_HEADER_LENGTH
  jmp @begin

@buildRequest:
  assert_m8_i16
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  sta pppTransmitBuffer + 4
  lda pppLcpRequestIdentifier
  sta pppTransmitBuffer + 5
  lda pppLcpLocalFlags
  and #PPP_LCP_LOCAL_FLAG_MAGIC_REQUEST
  beq @buildEmptyRequest
  stz pppTransmitBuffer + 6
  lda #(PPP_LCP_HEADER_LENGTH + 6)
  sta pppTransmitBuffer + 7
  lda #PPP_LCP_OPTION_MAGIC_NUMBER
  sta pppTransmitBuffer + 8
  lda #$06
  sta pppTransmitBuffer + 9
  lda pppLcpLocalMagic + 3
  sta pppTransmitBuffer + 10
  lda pppLcpLocalMagic + 2
  sta pppTransmitBuffer + 11
  lda pppLcpLocalMagic + 1
  sta pppTransmitBuffer + 12
  lda pppLcpLocalMagic + 0
  sta pppTransmitBuffer + 13
  m16
  lda #(PPP_LCP_MINIMUM_FRAME_LENGTH + 6)
  jmp @begin
@buildEmptyRequest:
  assert_m8_i16
  stz pppTransmitBuffer + 6
  lda #PPP_LCP_HEADER_LENGTH
  sta pppTransmitBuffer + 7
  m16
  lda #PPP_LCP_MINIMUM_FRAME_LENGTH
  jmp @begin

@buildTerminateRequest:
  assert_m8_i16
  lda #PPP_LCP_CODE_TERMINATE_REQUEST
  sta pppTransmitBuffer + 4
  lda pppLcpRequestIdentifier
  sta pppTransmitBuffer + 5
  stz pppTransmitBuffer + 6
  lda #PPP_LCP_HEADER_LENGTH
  sta pppTransmitBuffer + 7
  m16
  lda #PPP_LCP_MINIMUM_FRAME_LENGTH
  jmp @begin

@copyResponse:
  assert_m8_i16
  m16
  ldx #$0000
@copyLoop:
  assert_m16_i16
  cpx pppLcpPacketLength
  beq @selectResponseCode
  m8
  lda pppFrameBuffer + PPP_LCP_FRAME_OFFSET, x
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET, x
  m16
  inx
  bra @copyLoop

@selectResponseCode:
  assert_m16_i16
  m8
  lda #PPP_LCP_CODE_CONFIGURE_ACK
  assert_m8_i16
  sta pppTransmitBuffer + PPP_LCP_FRAME_OFFSET
  m16
  lda pppLcpPacketLength
  clc
  adc #PPP_UNCOMPRESSED_HEADER_LENGTH
  jmp @begin

@buildSelectiveResponse:
  assert_m8_i16
  m16
  jsr pppLcpBuildPeerResponse
  jmp @begin

@buildTerminateAck:
  assert_m8_i16
  lda #PPP_LCP_CODE_TERMINATE_ACK
  sta pppTransmitBuffer + 4
  lda pppLcpLastIdentifier
  sta pppTransmitBuffer + 5
  stz pppTransmitBuffer + 6
  lda #PPP_LCP_HEADER_LENGTH
  sta pppTransmitBuffer + 7
  m16
  lda #PPP_LCP_MINIMUM_FRAME_LENGTH
  jmp @begin

@buildProtocolReject:
  assert_m8_i16
  lda #PPP_LCP_CODE_PROTOCOL_REJECT
  sta pppTransmitBuffer + 4
  lda pppLcpRejectIdentifier
  sta pppTransmitBuffer + 5

  ; LCP Length includes its four-byte header. Limit it to the received frame,
  ; the peer MRU, and this build's fixed 1500-byte transmit Information area.
  m16
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
  m8
  sta pppTransmitBuffer + 6
  lda pppLcpOutputCursor
  sta pppTransmitBuffer + 7

  m16
  lda pppLcpOutputCursor
  sec
  sbc #PPP_LCP_HEADER_LENGTH
  sta pppLcpPacketEnd
  ldx #PPP_UNCOMPRESSED_HEADER_LENGTH - 2
  ldy #PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_LCP_HEADER_LENGTH
@copyRejectedFrame:
  assert_m16_i16
  lda pppLcpPacketEnd
  beq @protocolRejectLength
  m8
  lda pppFrameBuffer, x
  sta pppTransmitBuffer, y
  m16
  inx
  iny
  dec pppLcpPacketEnd
  bra @copyRejectedFrame

@protocolRejectLength:
  assert_m16_i16
  lda pppLcpOutputCursor
  clc
  adc #PPP_UNCOMPRESSED_HEADER_LENGTH
  jmp @begin

@buildCodeReject:
  assert_m8_i16
  lda #PPP_LCP_CODE_CODE_REJECT
  sta pppTransmitBuffer + 4
  lda pppLcpRejectIdentifier
  sta pppTransmitBuffer + 5

  ; Copy the complete Length-delimited rejected LCP packet when possible.
  ; The outer LCP packet is bounded by the peer MRU and the fixed transmit
  ; Information area. Preserve at least the rejected four-byte LCP header.
  m16
  lda pppLcpPacketLength
  clc
  adc #PPP_LCP_HEADER_LENGTH
  cmp pppLcpPeerMru
  bcc :+
  beq :+
  lda pppLcpPeerMru
:
  cmp #PPP_DEFAULT_MRU + 1
  bcc :+
  lda #PPP_DEFAULT_MRU
:
  cmp #(PPP_LCP_HEADER_LENGTH * 2)
  bcs :+
  lda #(PPP_LCP_HEADER_LENGTH * 2)
:
  sta pppLcpOutputCursor
  xba
  m8
  sta pppTransmitBuffer + 6
  lda pppLcpOutputCursor
  sta pppTransmitBuffer + 7

  m16
  lda pppLcpOutputCursor
  sec
  sbc #PPP_LCP_HEADER_LENGTH
  sta pppLcpPacketEnd
  ldx #PPP_LCP_FRAME_OFFSET
  ldy #PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_LCP_HEADER_LENGTH
@copyRejectedLcpPacket:
  assert_m16_i16
  lda pppLcpPacketEnd
  beq @codeRejectLength
  m8
  lda pppFrameBuffer, x
  sta pppTransmitBuffer, y
  m16
  inx
  iny
  dec pppLcpPacketEnd
  bra @copyRejectedLcpPacket

@codeRejectLength:
  assert_m16_i16
  lda pppLcpOutputCursor
  clc
  adc #PPP_UNCOMPRESSED_HEADER_LENGTH

@begin:
  assert_m16_i16
  jsr pppTransmitBegin
  bcs @busy16
  m8
  jsr pppSnapshotBegin
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_REQUEST
  beq @armRequestTimer
  cmp #PPP_LCP_ACTION_TERMINATE_REQUEST
  bne @maybeTerminateAck
  m16
  inc pppLcpLocalTerminateRequestCount
  bne :+
  inc pppLcpLocalTerminateRequestCount + 2
:
  m8
@armRequestTimer:
  assert_m8_i16
  jsr pppLcpArmRestartTimer
  bra :+
@maybeTerminateAck:
  cmp #PPP_LCP_ACTION_TERMINATE_ACK
  bne @maybeProtocolReject
  m16
  inc pppLcpTerminateAckCount
  bne :+
  inc pppLcpTerminateAckCount + 2
:
  m8
  bra @counterDone
@maybeProtocolReject:
  cmp #PPP_LCP_ACTION_PROTOCOL_REJECT
  bne @maybeCodeReject
  m16
  inc pppLcpProtocolRejectCount
  bne :+
  inc pppLcpProtocolRejectCount + 2
:
  m8
  bra @counterDone
@maybeCodeReject:
  cmp #PPP_LCP_ACTION_CODE_REJECT
  bne @maybeEchoReply
  m16
  inc pppLcpCodeRejectCount
  bne :+
  inc pppLcpCodeRejectCount + 2
:
  m8
  bra @counterDone
@maybeEchoReply:
  cmp #PPP_LCP_ACTION_ECHO_REPLY
  bne @counterDone
  m16
  inc pppLcpEchoReplyCount
  bne :+
  inc pppLcpEchoReplyCount + 2
:
  m8
@counterDone:
  stz pppLcpPendingAction
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

@busy16:
  assert_m16_i16
  m8
@busy:
  assert_m8_i16
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
  cmp #(PPP_LCP_HEADER_LENGTH + 6)
  beq :+
  jmp @fail31
:
  lda pppTransmitBuffer + 8
  cmp #PPP_LCP_OPTION_MAGIC_NUMBER
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
  jsl pppLcpWriteLocalAckTestPacket
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
  jsl pppLcpWriteLocalAckTestPacket
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

  ; A Nak that repeats our Magic is treated as a collision and advances the
  ; proposal before allocating the next request.
  m16
  lda pppLcpLocalMagic
  sta pppTransmitBuffer + 20
  lda pppLcpLocalMagic + 2
  sta pppTransmitBuffer + 22
  m8
  lda #PPP_LCP_CODE_CONFIGURE_NAK
  ldx #$0001
  jsl pppLcpWriteLocalAckTestPacket
  jsr pppLcpReceiveFrame
  bcc :+
  jmp @fail3d
:
  lda pppLcpRequestIdentifier
  cmp #$02
  beq :+
  jmp @fail3d
:
  m16
  lda pppTransmitBuffer + 20
  clc
  adc #PPP_LCP_MAGIC_RETRY_INCREMENT_LOW
  sta pppLcpOutputCursor
  lda pppTransmitBuffer + 22
  adc #PPP_LCP_MAGIC_RETRY_INCREMENT_HIGH
  cmp pppLcpLocalMagic + 2
  beq :+
  jmp @fail3d16
:
  lda pppLcpOutputCursor
  cmp pppLcpLocalMagic
  beq :+
  jmp @fail3d16
:
  m8

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
  pppLcpNegotiationRequireEqual @fail3a
  lda pppTransmitBuffer + 5
  cmp #$0a
  pppLcpNegotiationRequireEqual @fail3a
  lda pppTransmitBuffer + 8
  cmp #$01
  pppLcpNegotiationRequireEqual @fail3a
  lda pppTransmitBuffer + 9
  cmp #$04
  pppLcpNegotiationRequireEqual @fail3a

  ; Peer termination uses the peer Identifier and an empty Ack payload.
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_TERMINATE_REQUEST
  ldx #$0042
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  pppLcpNegotiationRequireCarryClear @fail3b
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_TERMINATE_ACK
  pppLcpNegotiationRequireEqual @fail3b
  jsr pppLcpBuildPending
  pppLcpNegotiationRequireCarryClear @fail3b
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_TERMINATE_ACK
  pppLcpNegotiationRequireEqual @fail3b
  lda pppTransmitBuffer + 5
  cmp #$42
  pppLcpNegotiationRequireEqual @fail3b
  lda pppTransmitBuffer + 7
  cmp #PPP_LCP_HEADER_LENGTH
  pppLcpNegotiationRequireEqual @fail3b

  ; A local Close sends Terminate-Request with a fresh Identifier and arms
  ; Max-Terminate only after the encoder accepts the packet.
  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  jsr pppLcpClose
  lda pppLcpAdministrativeOpen
  pppLcpNegotiationRequireEqual @fail3c
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSING
  pppLcpNegotiationRequireEqual @fail3c
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_TERMINATE_REQUEST
  pppLcpNegotiationRequireEqual @fail3c
  lda pppLcpRequestIdentifier
  cmp #$01
  pppLcpNegotiationRequireEqual @fail3c
  lda pppLcpRestartRemaining
  cmp #(PPP_LCP_DEFAULT_MAX_TERMINATE - 1)
  pppLcpNegotiationRequireEqual @fail3c
  jsr pppLcpBuildPending
  pppLcpNegotiationRequireCarryClear @fail3c
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_TERMINATE_REQUEST
  pppLcpNegotiationRequireEqual @fail3c
  lda pppTransmitBuffer + 5
  cmp #$01
  pppLcpNegotiationRequireEqual @fail3c
  lda pppTransmitBuffer + 7
  cmp #PPP_LCP_HEADER_LENGTH
  pppLcpNegotiationRequireEqual @fail3c
  lda pppLcpTimerActive
  pppLcpNegotiationRequireNonzero @fail3c
  m16
  lda pppLcpLocalTerminateRequestCount
  cmp #$0001
  m8
  pppLcpNegotiationRequireEqual @fail3c

  ; Matching Terminate-Ack completes Closed and keeps auto-Open disabled.
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_TERMINATE_ACK
  ldx #$0001
  jsr @writeEmptyPacket
  jsr pppLcpReceiveFrame
  pppLcpNegotiationRequireCarryClear @fail3f
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSED
  pppLcpNegotiationRequireEqual @fail3f
  lda pppLcpAdministrativeOpen
  pppLcpNegotiationRequireEqual @fail3f
  lda pppLcpRestartRemaining
  ora pppLcpPendingAction
  ora pppLcpTimerActive
  pppLcpNegotiationRequireEqual @fail3f
  m16
  lda pppLcpLocalTerminateAckCount
  cmp #$0001
  m8
  pppLcpNegotiationRequireEqual @fail3f

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
  bra @fail
@fail3c:
  lda #$3c
  bra @fail
@fail3d16:
  assert_m16_i16
  m8
@fail3d:
  lda #$3d
  bra @fail
@fail3f:
  lda #$3f

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
  assert_m8_i16
  sta pppFrameBuffer + 4
  txa
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #PPP_LCP_HEADER_LENGTH
  sta pppFrameBuffer + 7
  m16
  lda #PPP_PROTOCOL_LCP
  sta pppLastProtocol
  lda #PPP_LCP_MINIMUM_FRAME_LENGTH
  sta pppLastFrameLength
  m8
  rts

; Input A=Code, X low byte=Identifier. Adds MRU 1500.
@writeMruPacket:
  assert_m8_i16
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
  m16
  lda #PPP_PROTOCOL_LCP
  sta pppLastProtocol
  lda #$000c
  sta pppLastFrameLength
  m8
  rts
.endproc

.segment "BANK1_CODE"

; Long-call leaf: select another nonzero local Magic after a Nak collision.
.proc pppLcpAdvanceLocalMagic
  .a8
  .i16

  m16
  lda pppLcpLocalMagic
  clc
  adc #PPP_LCP_MAGIC_RETRY_INCREMENT_LOW
  sta pppLcpLocalMagic
  lda pppLcpLocalMagic + 2
  adc #PPP_LCP_MAGIC_RETRY_INCREMENT_HIGH
  sta pppLcpLocalMagic + 2
  ora pppLcpLocalMagic
  bne :+
  lda #PPP_LCP_MAGIC_RETRY_INCREMENT_LOW
  sta pppLcpLocalMagic
  lda #PPP_LCP_MAGIC_RETRY_INCREMENT_HIGH
  sta pppLcpLocalMagic + 2
:
  m8
  rtl
.endproc

; Long-call self-test helper. Input A=Code, X low byte=Identifier.
.proc pppLcpWriteLocalAckTestPacket
  .a8
  .i16

  sta pppFrameBuffer + 4
  txa
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #(PPP_LCP_HEADER_LENGTH + 6)
  sta pppFrameBuffer + 7
  lda #PPP_LCP_OPTION_MAGIC_NUMBER
  sta pppFrameBuffer + 8
  lda #$06
  sta pppFrameBuffer + 9
  lda pppLcpLocalMagic + 3
  sta pppFrameBuffer + 10
  lda pppLcpLocalMagic + 2
  sta pppFrameBuffer + 11
  lda pppLcpLocalMagic + 1
  sta pppFrameBuffer + 12
  lda pppLcpLocalMagic + 0
  sta pppFrameBuffer + 13
  m16
  lda #PPP_PROTOCOL_LCP
  sta pppLastProtocol
  lda #(PPP_LCP_MINIMUM_FRAME_LENGTH + 6)
  sta pppLastFrameLength
  m8
  rtl
.endproc
