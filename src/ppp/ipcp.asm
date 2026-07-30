.include "../macro/utility.asm"
.include "constants.inc"

.code

.import frameCounter
.import pppSnapshotBegin, pppSnapshotEnd
.import pppLastProtocol, pppLastFrameLength, pppFrameBuffer
.import pppTransmitActive, pppTransmitBuffer, pppTransmitBegin
.import pppTransmitInitialize
.import pppIpcpState, pppIpcpLastCode, pppIpcpLastIdentifier
.import pppIpcpLastError, pppIpcpRequestIdentifier, pppIpcpRestartRemaining
.import pppIpcpPendingAction, pppIpcpTimerActive, pppIpcpPacketLength
.import pppIpcpRestartDeadline, pppIpcpReceiveCount, pppIpcpTransmitCount
.import pppIpcpLocalAddress, pppIpcpPeerAddress, pppIpcpFlags
.import pppIpcpDeferredRequest
.import pppIpcpPacketEnd, pppIpcpOptionLength, pppIpcpOptionOffset
.import pppIpcpOutputCursor, pppIpcpHasReject, pppIpcpHasNak
.import pppIpcpOptionSeen, pppIpcpOptionDuplicate

.export pppIpcpInitialize, pppIpcpLowerUp, pppIpcpLowerDown
.export pppIpcpReceiveFrame, pppIpcpBuildPending, pppIpcpPollTimeout
.export pppIpcpRunSelfTest

.macro pppIpcpReturnError error
  lda #error
  sta pppIpcpLastError
  jsr pppSnapshotEnd
  ply
  plx
  plb
  sec
  rts
.endmacro

.macro pppIpcpRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

.proc pppIpcpInitialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppIpcpState
  stz pppIpcpLastCode
  stz pppIpcpLastIdentifier
  stz pppIpcpLastError
  stz pppIpcpRequestIdentifier
  stz pppIpcpRestartRemaining
  stz pppIpcpPendingAction
  stz pppIpcpTimerActive
  stz pppIpcpDeferredRequest
  lda #(PPP_IPCP_FLAG_REQUEST_ADDRESS | PPP_IPCP_FLAG_PEER_VALID)
  sta pppIpcpFlags
  stz pppIpcpLocalAddress + 0
  stz pppIpcpLocalAddress + 1
  stz pppIpcpLocalAddress + 2
  stz pppIpcpLocalAddress + 3
  jsr @setDefaultPeer
  rep #$20
  .a16
  stz pppIpcpPacketLength
  stz pppIpcpRestartDeadline
  stz pppIpcpReceiveCount
  stz pppIpcpReceiveCount + 2
  stz pppIpcpTransmitCount
  stz pppIpcpTransmitCount + 2
  sep #$20
  .a8
  plb
  rts

@setDefaultPeer:
  .a8
  lda #PPP_IPCP_PEER_ADDRESS_0
  sta pppIpcpPeerAddress + 0
  lda #PPP_IPCP_PEER_ADDRESS_1
  sta pppIpcpPeerAddress + 1
  lda #PPP_IPCP_PEER_ADDRESS_2
  sta pppIpcpPeerAddress + 2
  lda #PPP_IPCP_PEER_ADDRESS_3
  sta pppIpcpPeerAddress + 3
  rts
.endproc

; Enter IPCP after PAP reaches Opened. The initial request asks the peer to
; assign an address by proposing IP-Address 0.0.0.0.
.proc pppIpcpLowerUp
  .a8
  .i16

  phb
  setDBR $7e
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_CLOSED
  bne @done
  jsr pppSnapshotBegin
  lda #PPP_IPCP_STATE_REQUEST_SENT
  sta pppIpcpState
  lda #$01
  sta pppIpcpRequestIdentifier
  lda #(PPP_IPCP_DEFAULT_MAX_CONFIGURE - 1)
  sta pppIpcpRestartRemaining
  lda #PPP_IPCP_ACTION_CONFIGURE_REQUEST
  sta pppIpcpPendingAction
  stz pppIpcpTimerActive
  stz pppIpcpDeferredRequest
  stz pppIpcpLastError
  stz pppIpcpLocalAddress + 0
  stz pppIpcpLocalAddress + 1
  stz pppIpcpLocalAddress + 2
  stz pppIpcpLocalAddress + 3
  lda #(PPP_IPCP_FLAG_REQUEST_ADDRESS | PPP_IPCP_FLAG_PEER_VALID)
  sta pppIpcpFlags
  lda #PPP_IPCP_PEER_ADDRESS_0
  sta pppIpcpPeerAddress + 0
  lda #PPP_IPCP_PEER_ADDRESS_1
  sta pppIpcpPeerAddress + 1
  lda #PPP_IPCP_PEER_ADDRESS_2
  sta pppIpcpPeerAddress + 2
  lda #PPP_IPCP_PEER_ADDRESS_3
  sta pppIpcpPeerAddress + 3
  jsr pppSnapshotEnd
@done:
  plb
  rts
.endproc

.proc pppIpcpLowerDown
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  stz pppIpcpState
  stz pppIpcpRequestIdentifier
  stz pppIpcpRestartRemaining
  stz pppIpcpPendingAction
  stz pppIpcpTimerActive
  stz pppIpcpDeferredRequest
  stz pppIpcpPacketLength
  stz pppIpcpPacketLength + 1
  stz pppIpcpRestartDeadline
  stz pppIpcpRestartDeadline + 1
  stz pppIpcpLocalAddress + 0
  stz pppIpcpLocalAddress + 1
  stz pppIpcpLocalAddress + 2
  stz pppIpcpLocalAddress + 3
  lda #PPP_IPCP_PEER_ADDRESS_0
  sta pppIpcpPeerAddress + 0
  lda #PPP_IPCP_PEER_ADDRESS_1
  sta pppIpcpPeerAddress + 1
  lda #PPP_IPCP_PEER_ADDRESS_2
  sta pppIpcpPeerAddress + 2
  lda #PPP_IPCP_PEER_ADDRESS_3
  sta pppIpcpPeerAddress + 3
  lda #(PPP_IPCP_FLAG_REQUEST_ADDRESS | PPP_IPCP_FLAG_PEER_VALID)
  sta pppIpcpFlags
  jsr pppSnapshotEnd
  plb
  rts
.endproc

; Parse and apply one retained IPCP Configure packet.
;
; Carry clear means the packet was structurally valid, including unsupported
; Codes that are ignored by this milestone. Carry set reports a parser or
; response-validation error through pppIpcpLastError.
.proc pppIpcpReceiveFrame
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppSnapshotBegin
  pppIncrement32 pppIpcpReceiveCount
  stz pppIpcpLastCode
  stz pppIpcpLastIdentifier
  stz pppIpcpPacketLength
  stz pppIpcpPacketLength + 1

  rep #$20
  .a16
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_IPCP
  beq @checkHeader
  sep #$20
  .a8
  pppIpcpReturnError PPP_IPCP_ERROR_WRONG_PROTOCOL

@checkHeader:
  .a16
  lda pppLastFrameLength
  cmp #PPP_IPCP_MINIMUM_FRAME_LENGTH
  bcs @readHeader
  sep #$20
  .a8
  pppIpcpReturnError PPP_IPCP_ERROR_TRUNCATED_HEADER

@readHeader:
  sep #$20
  .a8
  lda pppFrameBuffer + PPP_IPCP_FRAME_OFFSET
  sta pppIpcpLastCode
  lda pppFrameBuffer + PPP_IPCP_FRAME_OFFSET + 1
  sta pppIpcpLastIdentifier
  lda pppFrameBuffer + PPP_IPCP_FRAME_OFFSET + 3
  sta pppIpcpPacketLength
  lda pppFrameBuffer + PPP_IPCP_FRAME_OFFSET + 2
  sta pppIpcpPacketLength + 1
  rep #$20
  .a16
  lda pppIpcpPacketLength
  cmp #PPP_IPCP_HEADER_LENGTH
  bcs @checkAvailable
  sep #$20
  .a8
  pppIpcpReturnError PPP_IPCP_ERROR_INVALID_PACKET_LENGTH

@checkAvailable:
  .a16
  clc
  adc #PPP_IPCP_FRAME_OFFSET
  sta pppIpcpPacketEnd
  cmp pppLastFrameLength
  bcc @validateOptions
  beq @validateOptions
  sep #$20
  .a8
  pppIpcpReturnError PPP_IPCP_ERROR_TRUNCATED_PACKET

@validateOptions:
  .a16
  sep #$20
  .a8
  lda pppIpcpLastCode
  cmp #PPP_IPCP_CODE_CONFIGURE_REQUEST
  beq @optionStart
  cmp #PPP_IPCP_CODE_CONFIGURE_REJECT + 1
  bcc @optionStart
  jmp @dispatch

@optionStart:
  .a8
  rep #$20
  .a16
  ldx #PPP_IPCP_FRAME_OFFSET + PPP_IPCP_HEADER_LENGTH
@optionLoop:
  .a16
  cpx pppIpcpPacketEnd
  beq @dispatch
  txa
  clc
  adc #$0002
  cmp pppIpcpPacketEnd
  bcc @readOptionLength
  beq @readOptionLength
  bra @truncatedOption16

@readOptionLength:
  .a16
  sep #$20
  .a8
  lda pppFrameBuffer + 1, x
  cmp #$02
  bcs @optionLength
  pppIpcpReturnError PPP_IPCP_ERROR_INVALID_OPTION_LENGTH

@optionLength:
  .a8
  sta pppIpcpOptionLength
  stz pppIpcpOptionLength + 1
  rep #$20
  .a16
  txa
  clc
  adc pppIpcpOptionLength
  cmp pppIpcpPacketEnd
  bcc @optionAdvance
  beq @optionAdvance
  sep #$20
  .a8
  pppIpcpReturnError PPP_IPCP_ERROR_OPTION_OVERRUN

@optionAdvance:
  .a16
  tax
  sep #$20
  .a8
  rep #$20
  .a16
  bra @optionLoop

@truncatedOption16:
  .a16
  sep #$20
  .a8
  pppIpcpReturnError PPP_IPCP_ERROR_TRUNCATED_OPTION

@dispatch:
  .a16
  sep #$20
  .a8
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_CLOSED
  beq @notConfiguring
  cmp #PPP_IPCP_STATE_STOPPED
  beq @notConfiguring
  lda pppIpcpLastCode
  cmp #PPP_IPCP_CODE_CONFIGURE_REQUEST
  beq @configureRequest
  cmp #PPP_IPCP_CODE_CONFIGURE_ACK
  bne :+
  jmp @configureAck
:
  cmp #PPP_IPCP_CODE_CONFIGURE_NAK
  bne :+
  jmp @configureNak
:
  cmp #PPP_IPCP_CODE_CONFIGURE_REJECT
  bne :+
  jmp @configureReject
:
  jmp @success

@notConfiguring:
  .a8
  pppIpcpReturnError PPP_IPCP_ERROR_NOT_CONFIGURING

@configureRequest:
  .a8
  jsr pppIpcpEvaluatePeerRequest
  sta pppIpcpPendingAction
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_OPENED
  beq @openedPeerRequest
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_ACK
  beq @acceptableRequest
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_ACK_RECEIVED
  bne :+
  jmp @success
:
  lda #PPP_IPCP_STATE_REQUEST_SENT
  sta pppIpcpState
  jmp @success

@openedPeerRequest:
  .a8
  inc pppIpcpRequestIdentifier
  lda #(PPP_IPCP_DEFAULT_MAX_CONFIGURE - 1)
  sta pppIpcpRestartRemaining
  stz pppIpcpTimerActive
  lda #$01
  sta pppIpcpDeferredRequest
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_ACK
  beq :+
  lda #PPP_IPCP_STATE_REQUEST_SENT
  sta pppIpcpState
  jmp @success
:
  lda #PPP_IPCP_STATE_ACK_SENT
  sta pppIpcpState
  jmp @success

@acceptableRequest:
  .a8
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_ACK_RECEIVED
  beq @requestCompletesOpen
  lda #PPP_IPCP_STATE_ACK_SENT
  sta pppIpcpState
  jmp @success

@requestCompletesOpen:
  .a8
  lda #PPP_IPCP_STATE_OPENED
  sta pppIpcpState
  stz pppIpcpRestartRemaining
  stz pppIpcpTimerActive
  jmp @success

@configureAck:
  .a8
  lda pppIpcpLastIdentifier
  cmp pppIpcpRequestIdentifier
  beq :+
  jmp @invalidResponse
:
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_REQUEST_ADDRESS
  beq @ackWithoutAddress
  rep #$20
  .a16
  lda pppIpcpPacketLength
  cmp #PPP_IPCP_CONFIGURE_PACKET_LENGTH
  beq :+
  jmp @invalidResponse16
:
  sep #$20
  .a8
  lda pppFrameBuffer + 8
  cmp #PPP_IPCP_OPTION_IP_ADDRESS
  beq :+
  jmp @invalidResponse
:
  lda pppFrameBuffer + 9
  cmp #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  beq :+
  jmp @invalidResponse
:
  ldx #$0000
@ackAddressLoop:
  lda pppFrameBuffer + 10, x
  cmp pppIpcpLocalAddress, x
  beq :+
  jmp @invalidResponse
:
  inx
  cpx #$0004
  bne @ackAddressLoop
  bra @applyAck

@ackWithoutAddress:
  .a8
  rep #$20
  .a16
  lda pppIpcpPacketLength
  cmp #PPP_IPCP_HEADER_LENGTH
  beq :+
  jmp @invalidResponse16
:
  sep #$20
  .a8

@applyAck:
  .a8
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_REQUEST_SENT
  beq @ackReceived
  cmp #PPP_IPCP_STATE_ACK_SENT
  beq @ackCompletesOpen
  cmp #PPP_IPCP_STATE_ACK_RECEIVED
  beq @restartAfterDuplicate
  cmp #PPP_IPCP_STATE_OPENED
  beq @restartAfterDuplicate
  jmp @success

@ackReceived:
  lda #PPP_IPCP_STATE_ACK_RECEIVED
  sta pppIpcpState
  lda #PPP_IPCP_DEFAULT_MAX_CONFIGURE
  sta pppIpcpRestartRemaining
  jmp @success

@ackCompletesOpen:
  lda #PPP_IPCP_STATE_OPENED
  sta pppIpcpState
  stz pppIpcpRestartRemaining
  stz pppIpcpTimerActive
  jmp @success

@restartAfterDuplicate:
  lda #PPP_IPCP_STATE_REQUEST_SENT
  sta pppIpcpState
  jsr @newRequest
  jmp @success

@configureNak:
  .a8
  lda pppIpcpLastIdentifier
  cmp pppIpcpRequestIdentifier
  bne @invalidResponse
  jsr @acceptAddressNak
  bcs @invalidResponse
  jsr @negativeResponse
  jmp @success

@configureReject:
  .a8
  lda pppIpcpLastIdentifier
  cmp pppIpcpRequestIdentifier
  bne @invalidResponse
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_REQUEST_ADDRESS
  beq @invalidResponse
  rep #$20
  .a16
  lda pppIpcpPacketLength
  cmp #PPP_IPCP_CONFIGURE_PACKET_LENGTH
  bne @invalidResponse16
  sep #$20
  .a8
  lda pppFrameBuffer + 8
  cmp #PPP_IPCP_OPTION_IP_ADDRESS
  bne @invalidResponse
  lda pppFrameBuffer + 9
  cmp #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  bne @invalidResponse
  ldx #$0000
@rejectAddressLoop:
  lda pppFrameBuffer + 10, x
  cmp pppIpcpLocalAddress, x
  bne @invalidResponse
  inx
  cpx #$0004
  bne @rejectAddressLoop
  lda pppIpcpFlags
  and #($ff ^ PPP_IPCP_FLAG_REQUEST_ADDRESS)
  sta pppIpcpFlags
  jsr @negativeResponse
  jmp @success

@invalidResponse16:
  .a16
  sep #$20
  .a8
@invalidResponse:
  .a8
  pppIpcpReturnError PPP_IPCP_ERROR_INVALID_RESPONSE

@success:
  .a8
  stz pppIpcpLastError
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

; Accept exactly one non-zero IP-Address suggestion from Configure-Nak.
@acceptAddressNak:
  .a8
  ldy #PPP_IPCP_FRAME_OFFSET + PPP_IPCP_HEADER_LENGTH
  stz pppIpcpHasNak
@nakLoop:
  cpy pppIpcpPacketEnd
  beq @nakDone
  lda pppFrameBuffer, y
  cmp #PPP_IPCP_OPTION_IP_ADDRESS
  bne @nakAdvance
  lda pppIpcpHasNak
  bne @nakInvalid
  lda pppFrameBuffer + 1, y
  cmp #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  bne @nakInvalid
  lda pppFrameBuffer + 2, y
  ora pppFrameBuffer + 3, y
  ora pppFrameBuffer + 4, y
  ora pppFrameBuffer + 5, y
  beq @nakInvalid
  lda #$01
  sta pppIpcpHasNak
  ldx #$0000
@copyNakAddress:
  lda pppFrameBuffer + 2, y
  sta pppIpcpLocalAddress, x
  iny
  inx
  cpx #$0004
  bne @copyNakAddress
  dey
  dey
  dey
  dey
@nakAdvance:
  lda pppFrameBuffer + 1, y
  sta pppIpcpOptionLength
  stz pppIpcpOptionLength + 1
  rep #$20
  .a16
  tya
  clc
  adc pppIpcpOptionLength
  tay
  sep #$20
  .a8
  bra @nakLoop
@nakDone:
  lda pppIpcpHasNak
  beq @nakInvalid
  lda pppIpcpFlags
  ora #(PPP_IPCP_FLAG_REQUEST_ADDRESS | PPP_IPCP_FLAG_LOCAL_VALID)
  sta pppIpcpFlags
  clc
  rts
@nakInvalid:
  sec
  rts

@negativeResponse:
  .a8
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_ACK_SENT
  beq :+
  lda #PPP_IPCP_STATE_REQUEST_SENT
  sta pppIpcpState
:
  jsr @newRequest
  rts

@newRequest:
  .a8
  inc pppIpcpRequestIdentifier
  lda #(PPP_IPCP_DEFAULT_MAX_CONFIGURE - 1)
  sta pppIpcpRestartRemaining
  stz pppIpcpTimerActive
  stz pppIpcpDeferredRequest
  lda #PPP_IPCP_ACTION_CONFIGURE_REQUEST
  sta pppIpcpPendingAction
  rts
.endproc

; Determine the response to a validated peer Configure-Request.
.proc pppIpcpEvaluatePeerRequest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  ldx #$0000
@clearMaps:
  stz pppIpcpOptionSeen, x
  stz pppIpcpOptionDuplicate, x
  inx
  cpx #$0100
  bne @clearMaps

  ldy #PPP_IPCP_FRAME_OFFSET + PPP_IPCP_HEADER_LENGTH
@duplicates:
  cpy pppIpcpPacketEnd
  beq @classifyStart
  lda pppFrameBuffer, y
  tax
  lda pppIpcpOptionSeen, x
  beq @first
  lda #$01
  sta pppIpcpOptionDuplicate, x
  bra @duplicateAdvance
@first:
  lda #$01
  sta pppIpcpOptionSeen, x
@duplicateAdvance:
  jsr @advanceY
  bra @duplicates

@classifyStart:
  stz pppIpcpHasReject
  stz pppIpcpHasNak
  ldy #PPP_IPCP_FRAME_OFFSET + PPP_IPCP_HEADER_LENGTH
@classify:
  cpy pppIpcpPacketEnd
  beq @select
  jsr pppIpcpClassifyPeerOption
  cmp #PPP_IPCP_OPTION_DISPOSITION_REJECT
  bne @maybeNak
  lda #$01
  sta pppIpcpHasReject
  bra @classifyAdvance
@maybeNak:
  cmp #PPP_IPCP_OPTION_DISPOSITION_NAK
  bne @classifyAdvance
  lda #$01
  sta pppIpcpHasNak
@classifyAdvance:
  jsr @advanceY
  bra @classify

@select:
  lda pppIpcpHasReject
  beq @selectNak
  lda #PPP_IPCP_ACTION_CONFIGURE_REJECT
  bra @return
@selectNak:
  lda pppIpcpHasNak
  beq @accept
  lda #PPP_IPCP_ACTION_CONFIGURE_NAK
  bra @return
@accept:
  ; Publish a peer address only after the complete request is acceptable.
  ldy #PPP_IPCP_FRAME_OFFSET + PPP_IPCP_HEADER_LENGTH
@commitLoop:
  cpy pppIpcpPacketEnd
  beq @accepted
  lda pppFrameBuffer, y
  cmp #PPP_IPCP_OPTION_IP_ADDRESS
  bne @commitAdvance
  ldx #$0000
@commitAddress:
  lda pppFrameBuffer + 2, y
  sta pppIpcpPeerAddress, x
  iny
  inx
  cpx #$0004
  bne @commitAddress
  dey
  dey
  dey
  dey
  lda pppIpcpFlags
  ora #PPP_IPCP_FLAG_PEER_VALID
  sta pppIpcpFlags
@commitAdvance:
  jsr @advanceY
  bra @commitLoop
@accepted:
  lda #PPP_IPCP_ACTION_CONFIGURE_ACK

@return:
  ply
  plx
  plb
  rts

@advanceY:
  lda pppFrameBuffer + 1, y
  sta pppIpcpOptionLength
  stz pppIpcpOptionLength + 1
  rep #$20
  .a16
  tya
  clc
  adc pppIpcpOptionLength
  tay
  sep #$20
  .a8
  rts
.endproc

.proc pppIpcpClassifyPeerOption
  .a8
  .i16

  phx
  lda pppFrameBuffer, y
  tax
  lda pppIpcpOptionDuplicate, x
  bne @reject
  txa
  cmp #PPP_IPCP_OPTION_IP_ADDRESS
  bne @reject
  lda pppFrameBuffer + 1, y
  cmp #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  bne @nak
  lda pppFrameBuffer + 2, y
  ora pppFrameBuffer + 3, y
  ora pppFrameBuffer + 4, y
  ora pppFrameBuffer + 5, y
  beq @nak
  plx
  lda #PPP_IPCP_OPTION_DISPOSITION_ACK
  rts
@nak:
  plx
  lda #PPP_IPCP_OPTION_DISPOSITION_NAK
  rts
@reject:
  plx
  lda #PPP_IPCP_OPTION_DISPOSITION_REJECT
  rts
.endproc

; Build a selective peer Nak or Reject. Output A16=unescaped frame length.
.proc pppIpcpBuildPeerResponse
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_NAK
  beq @nakCode
  lda #PPP_IPCP_CODE_CONFIGURE_REJECT
  bra @storeCode
@nakCode:
  lda #PPP_IPCP_CODE_CONFIGURE_NAK
@storeCode:
  sta pppTransmitBuffer + 4
  lda pppIpcpLastIdentifier
  sta pppTransmitBuffer + 5
  rep #$20
  .a16
  lda #PPP_IPCP_FRAME_OFFSET + PPP_IPCP_HEADER_LENGTH
  sta pppIpcpOutputCursor
  ldy #PPP_IPCP_FRAME_OFFSET + PPP_IPCP_HEADER_LENGTH

@loop:
  .a16
  cpy pppIpcpPacketEnd
  bne :+
  jmp @finish
:
  sep #$20
  .a8
  jsr pppIpcpClassifyPeerOption
  pha
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_REJECT
  beq @maybeReject
  pla
  cmp #PPP_IPCP_OPTION_DISPOSITION_NAK
  beq @writeNak
  bra @advance
@maybeReject:
  pla
  cmp #PPP_IPCP_OPTION_DISPOSITION_REJECT
  beq @copyOption
  bra @advance

@writeNak:
  ldx pppIpcpOutputCursor
  lda #PPP_IPCP_OPTION_IP_ADDRESS
  sta pppTransmitBuffer, x
  lda #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  sta pppTransmitBuffer + 1, x
  lda #PPP_IPCP_PEER_ADDRESS_0
  sta pppTransmitBuffer + 2, x
  lda #PPP_IPCP_PEER_ADDRESS_1
  sta pppTransmitBuffer + 3, x
  lda #PPP_IPCP_PEER_ADDRESS_2
  sta pppTransmitBuffer + 4, x
  lda #PPP_IPCP_PEER_ADDRESS_3
  sta pppTransmitBuffer + 5, x
  rep #$20
  .a16
  lda pppIpcpOutputCursor
  clc
  adc #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  sta pppIpcpOutputCursor
  sep #$20
  .a8
  bra @advance

@copyOption:
  sty pppIpcpOptionOffset
  lda pppFrameBuffer + 1, y
  sta pppIpcpOptionLength
  stz pppIpcpOptionLength + 1
@copyByte:
  ldy pppIpcpOptionOffset
  ldx pppIpcpOutputCursor
  lda pppFrameBuffer, y
  sta pppTransmitBuffer, x
  rep #$20
  .a16
  inc pppIpcpOptionOffset
  inc pppIpcpOutputCursor
  dec pppIpcpOptionLength
  lda pppIpcpOptionLength
  beq @copyDone
  sep #$20
  .a8
  bra @copyByte
@copyDone:
  .a16
  ldy pppIpcpOptionOffset
  jmp @loop

@advance:
  .a8
  lda pppFrameBuffer + 1, y
  sta pppIpcpOptionLength
  stz pppIpcpOptionLength + 1
  rep #$20
  .a16
  tya
  clc
  adc pppIpcpOptionLength
  tay
  jmp @loop

@finish:
  .a16
  lda pppIpcpOutputCursor
  sec
  sbc #PPP_IPCP_FRAME_OFFSET
  xba
  sep #$20
  .a8
  sta pppTransmitBuffer + 6
  xba
  sta pppTransmitBuffer + 7
  rep #$20
  .a16
  lda pppIpcpOutputCursor
  ply
  plx
  plb
  rts
.endproc

; Transfer one pending IPCP packet to the shared asynchronous encoder.
.proc pppIpcpBuildPending
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  lda pppIpcpPendingAction
  bne :+
  jmp busyReturn
:
  lda pppTransmitActive
  beq :+
  jmp busyReturn
:
  lda #$ff
  sta pppTransmitBuffer + 0
  lda #$03
  sta pppTransmitBuffer + 1
  lda #$80
  sta pppTransmitBuffer + 2
  lda #$21
  sta pppTransmitBuffer + 3
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_REQUEST
  beq @request
  cmp #PPP_IPCP_ACTION_CONFIGURE_ACK
  beq @ack
  cmp #PPP_IPCP_ACTION_CONFIGURE_NAK
  beq @selective
  cmp #PPP_IPCP_ACTION_CONFIGURE_REJECT
  beq @selective
  jmp busyReturn

@request:
  lda #PPP_IPCP_CODE_CONFIGURE_REQUEST
  sta pppTransmitBuffer + 4
  lda pppIpcpRequestIdentifier
  sta pppTransmitBuffer + 5
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_REQUEST_ADDRESS
  beq @emptyRequest
  stz pppTransmitBuffer + 6
  lda #PPP_IPCP_CONFIGURE_PACKET_LENGTH
  sta pppTransmitBuffer + 7
  lda #PPP_IPCP_OPTION_IP_ADDRESS
  sta pppTransmitBuffer + 8
  lda #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  sta pppTransmitBuffer + 9
  ldx #$0000
@requestAddress:
  lda pppIpcpLocalAddress, x
  sta pppTransmitBuffer + 10, x
  inx
  cpx #$0004
  bne @requestAddress
  rep #$20
  .a16
  lda #PPP_IPCP_CONFIGURE_FRAME_LENGTH
  bra @begin
@emptyRequest:
  stz pppTransmitBuffer + 6
  lda #PPP_IPCP_HEADER_LENGTH
  sta pppTransmitBuffer + 7
  rep #$20
  .a16
  lda #PPP_IPCP_MINIMUM_FRAME_LENGTH
  bra @begin

@ack:
  rep #$20
  .a16
  ldx #$0000
@ackCopy:
  cpx pppIpcpPacketLength
  beq @ackCode
  sep #$20
  .a8
  lda pppFrameBuffer + PPP_IPCP_FRAME_OFFSET, x
  sta pppTransmitBuffer + PPP_IPCP_FRAME_OFFSET, x
  rep #$20
  .a16
  inx
  bra @ackCopy
@ackCode:
  sep #$20
  .a8
  lda #PPP_IPCP_CODE_CONFIGURE_ACK
  sta pppTransmitBuffer + 4
  rep #$20
  .a16
  lda pppIpcpPacketLength
  clc
  adc #PPP_IPCP_FRAME_OFFSET
  bra @begin

@selective:
  sep #$20
  .a8
  jsr pppIpcpBuildPeerResponse

@begin:
  .a16
  jsr pppTransmitBegin
  bcs busy16Return
  sep #$20
  .a8
  jsr pppSnapshotBegin
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_REQUEST
  bne @accepted
  rep #$20
  .a16
  lda frameCounter
  clc
  adc #PPP_IPCP_RESTART_INTERVAL_FRAMES
  sta pppIpcpRestartDeadline
  sep #$20
  .a8
  lda #$01
  sta pppIpcpTimerActive
@accepted:
  stz pppIpcpPendingAction
  pppIncrement32 pppIpcpTransmitCount
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts
busy16Return:
  sep #$20
  .a8
busyReturn:
  ply
  plx
  plb
  sec
  rts
.endproc

.proc pppIpcpPollTimeout
  .a8
  .i16

  phb
  setDBR $7e
  lda pppIpcpTimerActive
  beq @unchanged
  rep #$20
  .a16
  lda frameCounter
  sec
  sbc pppIpcpRestartDeadline
  bmi @unchanged16
  sep #$20
  .a8
  jsr pppSnapshotBegin
  stz pppIpcpTimerActive
  stz pppIpcpDeferredRequest
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_REQUEST_SENT
  beq @configuring
  cmp #PPP_IPCP_STATE_ACK_RECEIVED
  beq @configuring
  cmp #PPP_IPCP_STATE_ACK_SENT
  bne @publish
@configuring:
  lda pppIpcpRestartRemaining
  beq @stopped
  dec pppIpcpRestartRemaining
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_ACK_RECEIVED
  bne :+
  lda #PPP_IPCP_STATE_REQUEST_SENT
  sta pppIpcpState
:
  lda #PPP_IPCP_ACTION_CONFIGURE_REQUEST
  sta pppIpcpPendingAction
  bra @publish
@stopped:
  lda #PPP_IPCP_STATE_STOPPED
  sta pppIpcpState
  stz pppIpcpRestartRemaining
  stz pppIpcpPendingAction
@publish:
  jsr pppSnapshotEnd
  plb
  sec
  rts
@unchanged16:
  sep #$20
  .a8
@unchanged:
  plb
  clc
  rts
.endproc

; Deterministic pppd-style address transcript. No modem access is performed.
; Failure steps $70-$76 are reserved for IPCP.
.proc pppIpcpRunSelfTest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpcpLowerUp
  jsr pppIpcpBuildPending
  bcc :+
  jmp @fail70
:
  lda pppTransmitBuffer + 2
  cmp #$80
  pppIpcpRequireEqual @fail70
  lda pppTransmitBuffer + 3
  cmp #$21
  pppIpcpRequireEqual @fail70
  lda pppTransmitBuffer + 4
  cmp #PPP_IPCP_CODE_CONFIGURE_REQUEST
  pppIpcpRequireEqual @fail70
  lda pppTransmitBuffer + 5
  cmp #$01
  pppIpcpRequireEqual @fail70
  lda pppTransmitBuffer + 7
  cmp #PPP_IPCP_CONFIGURE_PACKET_LENGTH
  pppIpcpRequireEqual @fail70

  ; Peer proposes 10.24.0.1 and is acknowledged.
  jsr pppTransmitInitialize
  lda #PPP_IPCP_CODE_CONFIGURE_REQUEST
  ldx #$000b
  jsr @writeAddressPacket
  lda #PPP_IPCP_PEER_ADDRESS_0
  sta pppFrameBuffer + 10
  lda #PPP_IPCP_PEER_ADDRESS_1
  sta pppFrameBuffer + 11
  lda #PPP_IPCP_PEER_ADDRESS_2
  sta pppFrameBuffer + 12
  lda #PPP_IPCP_PEER_ADDRESS_3
  sta pppFrameBuffer + 13
  jsr pppIpcpReceiveFrame
  bcc :+
  jmp @fail71
:
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_ACK_SENT
  pppIpcpRequireEqual @fail71
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_ACK
  pppIpcpRequireEqual @fail71
  jsr pppIpcpBuildPending
  bcc :+
  jmp @fail71
:
  lda pppTransmitBuffer + 4
  cmp #PPP_IPCP_CODE_CONFIGURE_ACK
  pppIpcpRequireEqual @fail71

  ; Server Naks 0.0.0.0 to the assigned SFC address 10.24.0.2.
  jsr pppTransmitInitialize
  lda #PPP_IPCP_CODE_CONFIGURE_NAK
  ldx #$0001
  jsr @writeAddressPacket
  lda #10
  sta pppFrameBuffer + 10
  lda #24
  sta pppFrameBuffer + 11
  stz pppFrameBuffer + 12
  lda #2
  sta pppFrameBuffer + 13
  jsr pppIpcpReceiveFrame
  bcc :+
  jmp @fail72
:
  lda pppIpcpRequestIdentifier
  cmp #$02
  pppIpcpRequireEqual @fail72
  lda pppIpcpLocalAddress + 0
  cmp #10
  pppIpcpRequireEqual @fail72
  lda pppIpcpLocalAddress + 1
  cmp #24
  pppIpcpRequireEqual @fail72
  lda pppIpcpLocalAddress + 3
  cmp #2
  pppIpcpRequireEqual @fail72

  jsr pppIpcpBuildPending
  bcc :+
  jmp @fail73
:
  lda pppTransmitBuffer + 5
  cmp #$02
  pppIpcpRequireEqual @fail73
  lda pppTransmitBuffer + 13
  cmp #$02
  pppIpcpRequireEqual @fail73

  ; Matching Ack completes the crossed negotiation.
  jsr pppTransmitInitialize
  lda #PPP_IPCP_CODE_CONFIGURE_ACK
  ldx #$0002
  jsr @writeAddressPacket
  lda #10
  sta pppFrameBuffer + 10
  lda #24
  sta pppFrameBuffer + 11
  stz pppFrameBuffer + 12
  lda #2
  sta pppFrameBuffer + 13
  jsr pppIpcpReceiveFrame
  bcc :+
  jmp @fail74
:
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_OPENED
  pppIpcpRequireEqual @fail74
  lda pppIpcpTimerActive
  ora pppIpcpPendingAction
  pppIpcpRequireEqual @fail74

  ; Zero peer address is Naked to 10.24.0.1.
  jsr pppIpcpLowerDown
  jsr pppIpcpLowerUp
  jsr pppTransmitInitialize
  lda #PPP_IPCP_CODE_CONFIGURE_REQUEST
  ldx #$000c
  jsr @writeAddressPacket
  stz pppFrameBuffer + 10
  stz pppFrameBuffer + 11
  stz pppFrameBuffer + 12
  stz pppFrameBuffer + 13
  jsr pppIpcpReceiveFrame
  bcc :+
  jmp @fail75
:
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_NAK
  pppIpcpRequireEqual @fail75
  jsr pppIpcpBuildPending
  bcc :+
  jmp @fail75
:
  lda pppTransmitBuffer + 4
  cmp #PPP_IPCP_CODE_CONFIGURE_NAK
  pppIpcpRequireEqual @fail75
  lda pppTransmitBuffer + 10
  cmp #PPP_IPCP_PEER_ADDRESS_0
  pppIpcpRequireEqual @fail75

  ; IP compression is rejected verbatim.
  jsr pppTransmitInitialize
  lda #PPP_IPCP_CODE_CONFIGURE_REQUEST
  ldx #$000d
  jsr @writeCompressionPacket
  jsr pppIpcpReceiveFrame
  bcc :+
  jmp @fail76
:
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_REJECT
  pppIpcpRequireEqual @fail76
  jsr pppIpcpBuildPending
  bcc :+
  jmp @fail76
:
  lda pppTransmitBuffer + 4
  cmp #PPP_IPCP_CODE_CONFIGURE_REJECT
  pppIpcpRequireEqual @fail76
  lda pppTransmitBuffer + 8
  cmp #PPP_IPCP_OPTION_IP_COMPRESSION
  pppIpcpRequireEqual @fail76

  jsr @cleanup
  lda #$00
  clc
  bra @return
@fail70:
  lda #$70
  bra @fail
@fail71:
  lda #$71
  bra @fail
@fail72:
  lda #$72
  bra @fail
@fail73:
  lda #$73
  bra @fail
@fail74:
  lda #$74
  bra @fail
@fail75:
  lda #$75
  bra @fail
@fail76:
  lda #$76
@fail:
  pha
  jsr @cleanup
  pla
  sec
@return:
  ply
  plx
  plb
  rts

@cleanup:
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  rts

; Input A=Code, X low byte=Identifier.
@writeAddressPacket:
  sta pppFrameBuffer + 4
  txa
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #PPP_IPCP_CONFIGURE_PACKET_LENGTH
  sta pppFrameBuffer + 7
  lda #PPP_IPCP_OPTION_IP_ADDRESS
  sta pppFrameBuffer + 8
  lda #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  sta pppFrameBuffer + 9
  rep #$20
  .a16
  lda #PPP_PROTOCOL_IPCP
  sta pppLastProtocol
  lda #PPP_IPCP_CONFIGURE_FRAME_LENGTH
  sta pppLastFrameLength
  sep #$20
  .a8
  rts

@writeCompressionPacket:
  sta pppFrameBuffer + 4
  txa
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #$08
  sta pppFrameBuffer + 7
  lda #PPP_IPCP_OPTION_IP_COMPRESSION
  sta pppFrameBuffer + 8
  lda #$04
  sta pppFrameBuffer + 9
  stz pppFrameBuffer + 10
  stz pppFrameBuffer + 11
  rep #$20
  .a16
  lda #PPP_PROTOCOL_IPCP
  sta pppLastProtocol
  lda #$000c
  sta pppLastFrameLength
  sep #$20
  .a8
  rts
.endproc
