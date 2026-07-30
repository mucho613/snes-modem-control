.include "../macro/utility.asm"
.include "constants.inc"

.code

.import frameCounter
.import pppSnapshotBegin, pppSnapshotEnd
.import pppLastProtocol, pppLastFrameLength, pppFrameBuffer
.import pppTransmitActive, pppTransmitBuffer, pppTransmitBegin
.import pppTransmitInitialize
.import pppLcpInitialize, pppLcpPeerFlags
.import pppPapState, pppPapLastCode, pppPapLastIdentifier, pppPapLastError
.import pppPapRequestIdentifier, pppPapNextIdentifier
.import pppPapRestartRemaining, pppPapPendingAction
.import pppPapTimerActive, pppPapFailure, pppPapPacketLength
.import pppPapRestartDeadline, pppPapReceiveCount, pppPapTransmitCount
.import pppPapCredentialFlags, pppPapPeerIdLength, pppPapPasswordLength
.import pppPapPeerId, pppPapPassword
.import pppPapCredentialsReady, pppPapCredentialsClearSensitive

.export pppPapInitialize, pppPapLowerUp, pppPapLowerDown
.export pppPapBuildPending, pppPapReceiveFrame, pppPapPollTimeout
.export pppPapRunSelfTest

.proc pppPapInitialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppPapState
  stz pppPapLastCode
  stz pppPapLastIdentifier
  stz pppPapLastError
  stz pppPapRequestIdentifier
  lda #$01
  sta pppPapNextIdentifier
  stz pppPapRestartRemaining
  stz pppPapPendingAction
  stz pppPapTimerActive
  stz pppPapFailure
  m16
  stz pppPapPacketLength
  stz pppPapRestartDeadline
  stz pppPapReceiveCount
  stz pppPapReceiveCount + 2
  stz pppPapTransmitCount
  stz pppPapTransmitCount + 2
  m8
  plb
  rts
.endproc

; Enter the authentication phase once LCP reaches Opened.
.proc pppPapLowerUp
  .a8
  .i16

  phb
  setDBR $7e
  lda pppPapState
  bne @done
  jsr pppSnapshotBegin
  stz pppPapFailure
  stz pppPapTimerActive
  lda #PPP_PAP_DEFAULT_MAX_AUTHENTICATE
  sta pppPapRestartRemaining
  lda pppLcpPeerFlags
  and #PPP_LCP_PEER_FLAG_PAP
  beq @notRequired
  jsl pppPapCredentialsReady
  bcc @credentialsReady
  lda #PPP_PAP_STATE_FAILED
  sta pppPapState
  lda #PPP_PAP_FAILURE_CREDENTIALS_MISSING
  sta pppPapFailure
  stz pppPapPendingAction
  bra @publish
@credentialsReady:
  assert_m8_i16
  lda #PPP_PAP_STATE_REQUEST_PENDING
  sta pppPapState
  lda #PPP_PAP_ACTION_AUTHENTICATE_REQUEST
  sta pppPapPendingAction
  bra @publish
@notRequired:
  lda #PPP_PAP_STATE_OPENED
  sta pppPapState
  stz pppPapPendingAction
@publish:
  jsr pppSnapshotEnd
@done:
  plb
  rts
.endproc

.proc pppPapLowerDown
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  stz pppPapState
  stz pppPapRequestIdentifier
  stz pppPapRestartRemaining
  stz pppPapPendingAction
  stz pppPapTimerActive
  stz pppPapFailure
  m16
  stz pppPapPacketLength
  stz pppPapRestartDeadline
  m8
  jsr pppSnapshotEnd
  jsl pppPapCredentialsClearSensitive
  plb
  rts
.endproc

; Build the currently staged credential fields and transfer them to the shared
; asynchronous encoder. Only their lengths and presence flags are public.
;
; Carry clear means accepted. Carry set means the shared encoder is busy.
.proc pppPapBuildPending
  .a8
  .i16

  phb
  setDBR $7e
  lda pppPapPendingAction
  cmp #PPP_PAP_ACTION_AUTHENTICATE_REQUEST
  beq @build
  plb
  clc
  rts

@build:
  jsl pppPapCredentialsReady
  bcc :+
  jsr pppSnapshotBegin
  lda #PPP_PAP_STATE_FAILED
  sta pppPapState
  lda #PPP_PAP_FAILURE_CREDENTIALS_MISSING
  sta pppPapFailure
  stz pppPapPendingAction
  jsr pppSnapshotEnd
  plb
  clc
  rts
:
  ; Do not overwrite the unescaped source of an active LCP or PAP frame.
  lda pppTransmitActive
  beq :+
  plb
  sec
  rts
:
  lda #$ff
  sta pppTransmitBuffer + 0
  lda #$03
  sta pppTransmitBuffer + 1
  lda #$c0
  sta pppTransmitBuffer + 2
  lda #$23
  sta pppTransmitBuffer + 3
  lda #PPP_PAP_CODE_AUTHENTICATE_REQUEST
  sta pppTransmitBuffer + 4
  lda pppPapNextIdentifier
  sta pppTransmitBuffer + 5
  stz pppTransmitBuffer + 6
  lda pppPapPeerIdLength
  clc
  adc pppPapPasswordLength
  adc #(PPP_PAP_HEADER_LENGTH + 2)
  sta pppTransmitBuffer + 7
  lda pppPapPeerIdLength
  sta pppTransmitBuffer + 8
  i8
  ldx #$00
  ldy #$09
@copyPeerId:
  lda pppPapPeerId, x
  sta pppTransmitBuffer, y
  inx
  iny
  cpx pppPapPeerIdLength
  bne @copyPeerId
  lda pppPapPasswordLength
  sta pppTransmitBuffer, y
  iny
  ldx #$00
@copyPassword:
  lda pppPapPassword, x
  sta pppTransmitBuffer, y
  inx
  iny
  cpx pppPapPasswordLength
  bne @copyPassword
  i16
  m16
  tya
  jsr pppTransmitBegin
  m8
  bcs busyReturn

  jsr pppSnapshotBegin
  lda pppPapCredentialFlags
  and #PPP_PAP_CREDENTIAL_FLAG_TRANSIENT
  beq :+
  lda pppPapCredentialFlags
  ora #PPP_PAP_CREDENTIAL_FLAG_EXPOSURE_ACTIVE
  sta pppPapCredentialFlags
:
  lda pppPapNextIdentifier
  sta pppPapRequestIdentifier
  inc pppPapNextIdentifier
  dec pppPapRestartRemaining
  stz pppPapPendingAction
  lda #PPP_PAP_STATE_WAITING_FOR_REPLY
  sta pppPapState
  pppIncrement32 pppPapTransmitCount
  m16
  lda frameCounter
  clc
  adc #PPP_PAP_RESTART_INTERVAL_FRAMES
  sta pppPapRestartDeadline
  m8
  lda #$01
  sta pppPapTimerActive
  jsr pppSnapshotEnd
  plb
  clc
  rts

busyReturn:
  plb
  sec
  rts
.endproc

.macro pppPapReturnError error
  lda #error
  sta pppPapLastError
  jsr pppSnapshotEnd
  plb
  sec
  rts
.endmacro

; Parse and apply Authenticate-Ack/Nak from the retained PPP frame.
.proc pppPapReceiveFrame
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  pppIncrement32 pppPapReceiveCount
  stz pppPapLastCode
  stz pppPapLastIdentifier
  m16
  stz pppPapPacketLength
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_PAP
  beq @checkHeader
  m8
  pppPapReturnError PPP_PAP_ERROR_WRONG_PROTOCOL

@checkHeader:
  assert_m16_i16
  lda pppLastFrameLength
  cmp #PPP_PAP_MINIMUM_FRAME_LENGTH
  bcs @readHeader
  m8
  pppPapReturnError PPP_PAP_ERROR_TRUNCATED_HEADER

@readHeader:
  m8
  lda pppFrameBuffer + PPP_PAP_FRAME_OFFSET
  sta pppPapLastCode
  lda pppFrameBuffer + PPP_PAP_FRAME_OFFSET + 1
  sta pppPapLastIdentifier
  lda pppFrameBuffer + PPP_PAP_FRAME_OFFSET + 3
  sta pppPapPacketLength
  lda pppFrameBuffer + PPP_PAP_FRAME_OFFSET + 2
  sta pppPapPacketLength + 1
  m16
  lda pppPapPacketLength
  cmp #PPP_PAP_HEADER_LENGTH
  bcs @checkAvailable
  m8
  pppPapReturnError PPP_PAP_ERROR_INVALID_PACKET_LENGTH

@checkAvailable:
  assert_m16_i16
  clc
  adc #PPP_PAP_FRAME_OFFSET
  cmp pppLastFrameLength
  bcc @checkState
  beq @checkState
  m8
  pppPapReturnError PPP_PAP_ERROR_TRUNCATED_PACKET

@checkState:
  m8
  lda pppPapState
  cmp #PPP_PAP_STATE_WAITING_FOR_REPLY
  beq @checkCode
  pppPapReturnError PPP_PAP_ERROR_UNSUPPORTED_CODE

@checkCode:
  lda pppPapLastCode
  cmp #PPP_PAP_CODE_AUTHENTICATE_ACK
  beq @checkIdentifier
  cmp #PPP_PAP_CODE_AUTHENTICATE_NAK
  beq @checkIdentifier
  pppPapReturnError PPP_PAP_ERROR_UNSUPPORTED_CODE

@checkIdentifier:
  lda pppPapLastIdentifier
  cmp pppPapRequestIdentifier
  beq @checkMessage
  pppPapReturnError PPP_PAP_ERROR_IDENTIFIER_MISMATCH

@checkMessage:
  m16
  lda pppPapPacketLength
  cmp #PPP_PAP_HEADER_LENGTH + 1
  bcs @messagePresent
  m8
  pppPapReturnError PPP_PAP_ERROR_MESSAGE_LENGTH_MISSING

@messagePresent:
  m8
  lda pppFrameBuffer + PPP_PAP_FRAME_OFFSET + PPP_PAP_HEADER_LENGTH
  m16
  and #$00ff
  clc
  adc #PPP_PAP_HEADER_LENGTH + 1
  cmp pppPapPacketLength
  beq @accepted
  bcc @trailing
  m8
  pppPapReturnError PPP_PAP_ERROR_MESSAGE_TRUNCATED

@trailing:
  m8
  pppPapReturnError PPP_PAP_ERROR_TRAILING_DATA

@accepted:
  m8
  stz pppPapLastError
  stz pppPapTimerActive
  lda pppPapLastCode
  cmp #PPP_PAP_CODE_AUTHENTICATE_ACK
  beq @ack
  lda #PPP_PAP_STATE_FAILED
  sta pppPapState
  lda #PPP_PAP_FAILURE_REJECTED
  sta pppPapFailure
  bra @success
@ack:
  lda #PPP_PAP_STATE_OPENED
  sta pppPapState
  stz pppPapFailure
@success:
  jsr pppSnapshotEnd
  jsl pppPapCredentialsClearSensitive
  plb
  clc
  rts

.endproc

.proc pppPapPollTimeout
  .a8
  .i16

  phb
  setDBR $7e
  lda pppPapTimerActive
  bne @checkDeadline
  plb
  clc
  rts

@checkDeadline:
  m16
  lda frameCounter
  sec
  sbc pppPapRestartDeadline
  bmi @unchanged
  m8
  jsr pppSnapshotBegin
  stz pppPapTimerActive
  lda pppPapState
  cmp #PPP_PAP_STATE_WAITING_FOR_REPLY
  bne @publish
  lda pppPapRestartRemaining
  beq @failed
  lda #PPP_PAP_STATE_REQUEST_PENDING
  sta pppPapState
  lda #PPP_PAP_ACTION_AUTHENTICATE_REQUEST
  sta pppPapPendingAction
  bra @publish
@failed:
  lda #PPP_PAP_STATE_FAILED
  sta pppPapState
  lda #PPP_PAP_FAILURE_RETRY_LIMIT
  sta pppPapFailure
  jsl pppPapCredentialsClearSensitive
@publish:
  jsr pppSnapshotEnd
  plb
  sec
  rts

@unchanged:
  m8
  plb
  clc
  rts
.endproc

.macro pppPapRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; Deterministic fixture for request construction, Identifier matching, Ack,
; and lower-down. It does not access the NDM24 controller port.
;
; Output:
;   Carry clear, A=$00: passed
;   Carry set, A=$6A-$6D: failed step
.proc pppPapRunSelfTest
  .a8
  .i16

  jsr pppTransmitInitialize
  jsr pppPapInitialize
  lda #PPP_LCP_PEER_FLAG_PAP
  sta pppLcpPeerFlags
  jsr pppPapLowerUp
  lda pppPapState
  cmp #PPP_PAP_STATE_REQUEST_PENDING
  pppPapRequireEqual @fail6a
  jsr pppPapBuildPending
  bcc :+
  jmp @fail6a
:
  lda pppPapState
  cmp #PPP_PAP_STATE_WAITING_FOR_REPLY
  pppPapRequireEqual @fail6a
  lda pppPapRequestIdentifier
  cmp #$01
  pppPapRequireEqual @fail6a
  lda pppPapNextIdentifier
  cmp #$02
  pppPapRequireEqual @fail6a
  lda pppPapRestartRemaining
  cmp #(PPP_PAP_DEFAULT_MAX_AUTHENTICATE - 1)
  pppPapRequireEqual @fail6a

  lda pppTransmitBuffer + 0
  cmp #$ff
  pppPapRequireEqual @fail6b
  lda pppTransmitBuffer + 2
  cmp #$c0
  pppPapRequireEqual @fail6b
  lda pppTransmitBuffer + 3
  cmp #$23
  pppPapRequireEqual @fail6b
  lda pppTransmitBuffer + 4
  cmp #PPP_PAP_CODE_AUTHENTICATE_REQUEST
  pppPapRequireEqual @fail6b
  lda pppTransmitBuffer + 5
  cmp #$01
  pppPapRequireEqual @fail6b
  lda pppTransmitBuffer + 8
  cmp #PPP_PAP_PEER_ID_LENGTH
  pppPapRequireEqual @fail6b
  lda pppTransmitBuffer + 14
  cmp #PPP_PAP_PASSWORD_LENGTH
  pppPapRequireEqual @fail6b

  ; A wrong Identifier is ignored without stopping the timer.
  lda #PPP_PAP_CODE_AUTHENTICATE_ACK
  ldx #$0002
  jsr @writeReply
  jsr pppPapReceiveFrame
  bcs :+
  jmp @fail6c
:
  lda pppPapLastError
  cmp #PPP_PAP_ERROR_IDENTIFIER_MISMATCH
  pppPapRequireEqual @fail6c
  lda pppPapState
  cmp #PPP_PAP_STATE_WAITING_FOR_REPLY
  pppPapRequireEqual @fail6e
  lda pppPapTimerActive
  bne :+
  jmp @fail6f
:
  ; The matching Ack opens PAP and stops its timer.
  lda #PPP_PAP_CODE_AUTHENTICATE_ACK
  ldx #$0001
  jsr @writeReply
  jsr pppPapReceiveFrame
  bcc :+
  jmp @fail6d
:
  lda pppPapState
  cmp #PPP_PAP_STATE_OPENED
  pppPapRequireEqual @fail6d
  lda pppPapTimerActive
  ora pppPapFailure
  pppPapRequireEqual @fail6d

  jsr pppPapLowerDown
  lda pppPapState
  pppPapRequireEqual @fail6d
  lda #$00
  bra @cleanup

@fail6a:
  lda #$6a
  bra @cleanup
@fail6b:
  lda #$6b
  bra @cleanup
@fail6c:
  lda #$6c
  bra @cleanup
@fail6d:
  lda #$6d
  bra @cleanup
@fail6e:
  lda #$6e
  bra @cleanup
@fail6f:
  lda #$6f

@cleanup:
  pha
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
  jsr pppPapInitialize
  pla
  cmp #$00
  beq @passed
  sec
  rts
@passed:
  clc
  rts

; Input A=Code, X low byte=Identifier. Empty message.
@writeReply:
  sta pppFrameBuffer + 4
  txa
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #PPP_PAP_HEADER_LENGTH + 1
  sta pppFrameBuffer + 7
  stz pppFrameBuffer + 8
  m16
  lda #PPP_PROTOCOL_PAP
  sta pppLastProtocol
  lda #PPP_PAP_MINIMUM_FRAME_LENGTH + 1
  sta pppLastFrameLength
  m8
  rts
.endproc
