.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import modemDriverState
.import pppReceiveEnabled, pppFrameReady, pppReleaseFrame
.import pppReceiveInitialize
.import pppTransmitActive, pppTransmitBuffer
.import pppTransmitInitialize, pppTransmitAbort
.import pppLcpState, pppLcpPendingAction, pppLcpTimerActive
.import pppLcpDeferredRequest, pppLcpPollAction
.import pppLcpPollSavedModemState
.import pppLcpProtocolRejectCount, pppLcpLastRejectedProtocol
.import pppLcpRejectIdentifier
.import pppLcpCodeRejectCount, pppLcpLastRejectedCode
.import pppLcpInitialize, pppLcpOpen, pppLcpReceiveFrame
.import pppLcpRejectProtocol
.import pppLcpBuildPending, pppLcpPollTimeout, pppLcpLowerDown
.import pppLcpPeerTerminateComplete
.import pppLastProtocol, pppLastFrameLength, pppFrameBuffer

.export pppLcpPoll, pppLcpPollRunSelfTest

; Own completed LCP frames and serialize them through the shared encoder.
; This runs after pppReceivePoll and before pppTransmitPoll.
.proc pppLcpPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e
  m8
  lda pppReceiveEnabled
  bne :+
  jmp @lowerUnavailable
:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq :+
  jmp @lowerUnavailable
:

  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSED
  beq @open
  cmp #PPP_LCP_STATE_STOPPED
  beq @stopped

@serviceExistingPending:
  .a8
  jsr @servicePending
  bcc :+
  jmp @done
:
  lda pppFrameReady
  beq @timer
  m16
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_LCP
  beq @receiveLcp
  cmp #PPP_PROTOCOL_PAP
  beq @knownUpperProtocol
  cmp #PPP_PROTOCOL_IPCP
  beq @knownUpperProtocol
  cmp #PPP_PROTOCOL_IP
  beq @knownUpperProtocol
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  bne :+
  jsr pppLcpRejectProtocol
  jsr @servicePending
  bcs @done
  bra @timer
:
  jsr pppReleaseFrame
  bra @timer

@knownUpperProtocol:
  .a16
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  beq @timer
  jsr pppReleaseFrame
  bra @timer

@open:
  .a8
  jsr pppLcpOpen
  bra @serviceExistingPending

@stopped:
  .a8
  lda pppFrameReady
  beq @done
  jsr pppReleaseFrame
  bra @done

@receiveLcp:
  .a16
  m8
  jsr pppLcpReceiveFrame
  bcs @releaseThenTimer

  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  beq @responsePending
  cmp #PPP_LCP_ACTION_CONFIGURE_NAK
  beq @responsePending
  cmp #PPP_LCP_ACTION_CONFIGURE_REJECT
  beq @responsePending
  cmp #PPP_LCP_ACTION_TERMINATE_ACK
  beq @responsePending
  cmp #PPP_LCP_ACTION_CODE_REJECT
  beq @responsePending

@releaseThenTimer:
  .a8
  jsr pppReleaseFrame
  jsr @servicePending
  bra @timer

@responsePending:
  .a8
  ; A busy encoder keeps both the response action and receive-frame ownership.
  jsr @servicePending
  bcs @done

@timer:
  .a8
  jsr pppLcpPollTimeout
  .a8
  jsr @servicePending
  bra @done

@lowerUnavailable:
  .a8
  lda pppFrameReady
  beq :+
  jsr pppReleaseFrame
:
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSED
  beq :+
  jsr pppLcpLowerDown
:
  jsr pppTransmitAbort

@done:
  .a8
  mi16
  ply
  plx
  plb
  pla
  rts

; Try to transfer one pending action to the encoder.
;
; Carry set means encoder backpressure. A response retains frame ownership
; until success. After a response succeeds, an Opened renegotiation request is
; promoted from the one-byte deferred slot.
@servicePending:
  .a8
  lda pppLcpPendingAction
  beq @serviceReady
  sta pppLcpPollAction
  jsr pppLcpBuildPending
  bcs @serviceBusy

  lda pppLcpPollAction
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  beq @responseSent
  cmp #PPP_LCP_ACTION_CONFIGURE_NAK
  beq @responseSent
  cmp #PPP_LCP_ACTION_CONFIGURE_REJECT
  beq @responseSent
  cmp #PPP_LCP_ACTION_TERMINATE_ACK
  beq @terminateAckSent
  cmp #PPP_LCP_ACTION_PROTOCOL_REJECT
  beq @responseSent
  cmp #PPP_LCP_ACTION_CODE_REJECT
  beq @responseSent
  bne @serviceReady

@terminateAckSent:
  .a8
  lda pppFrameReady
  beq :+
  jsr pppReleaseFrame
:
  jsr pppLcpPeerTerminateComplete
  bra @serviceReady

@responseSent:
  .a8
  lda pppFrameReady
  beq :+
  jsr pppReleaseFrame
:
  lda pppLcpDeferredRequest
  beq @serviceReady
  stz pppLcpDeferredRequest
  lda #PPP_LCP_ACTION_CONFIGURE_REQUEST
  sta pppLcpPendingAction

@serviceReady:
  .a8
  clc
  rts
@serviceBusy:
  .a8
  sec
  rts
.endproc

.macro pppLcpPollRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

.macro pppLcpPollRequireNonzero failure
  bne :+
  jmp failure
:
.endmacro

; Simulated main-loop transcript including encoder backpressure and Opened
; renegotiation. It never reads or writes the NDM24 controller port.
;
; Output:
;   Carry clear, A=$00: passed
;   Carry set, A=$60-$66: failed step
.proc pppLcpPollRunSelfTest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  lda modemDriverState
  sta pppLcpPollSavedModemState
  jsr pppReceiveInitialize
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
  lda #MODEM_STATE_CONNECTED
  sta modemDriverState
  lda #$01
  sta pppReceiveEnabled

  ; Closed + enabled + CONNECTED sends the initial local request.
  m16
  jsr pppLcpPoll
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_REQUEST_SENT
  pppLcpPollRequireEqual @fail60
  lda pppLcpPendingAction
  pppLcpPollRequireEqual @fail60
  lda pppTransmitActive
  pppLcpPollRequireNonzero @fail60
  lda pppLcpTimerActive
  pppLcpPollRequireNonzero @fail60

  ; A peer request arriving while TX is busy remains owned with its Ack.
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  ldx #$0007
  jsr @writeEmptyPacket
  m16
  jsr pppLcpPoll
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_SENT
  pppLcpPollRequireEqual @fail61
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  pppLcpPollRequireEqual @fail61
  lda pppFrameReady
  pppLcpPollRequireNonzero @fail61

  ; Once the encoder is idle, Ack is built and the frame is released.
  jsr pppTransmitInitialize
  m16
  jsr pppLcpPoll
  m8
  lda pppFrameReady
  pppLcpPollRequireEqual @fail62
  lda pppLcpPendingAction
  pppLcpPollRequireEqual @fail62
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CONFIGURE_ACK
  pppLcpPollRequireEqual @fail62
  lda pppTransmitBuffer + 5
  cmp #$07
  pppLcpPollRequireEqual @fail62

  ; Peer Ack of the local empty request completes Opened.
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_CONFIGURE_ACK
  ldx #$0000
  jsr @writeEmptyPacket
  m16
  jsr pppLcpPoll
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  pppLcpPollRequireEqual @fail63
  lda pppFrameReady
  ora pppLcpPendingAction
  ora pppLcpTimerActive
  pppLcpPollRequireEqual @fail63

  ; An unknown PPP protocol is rejected while Opened, including its
  ; uncompressed Protocol field and retained Information.
  lda #$ff
  sta pppFrameBuffer + 0
  lda #$03
  sta pppFrameBuffer + 1
  lda #$80
  sta pppFrameBuffer + 2
  lda #$57
  sta pppFrameBuffer + 3
  lda #$aa
  sta pppFrameBuffer + 4
  lda #$bb
  sta pppFrameBuffer + 5
  lda #$cc
  sta pppFrameBuffer + 6
  m16
  lda #$8057
  sta pppLastProtocol
  lda #$0007
  sta pppLastFrameLength
  m8
  lda #$01
  sta pppFrameReady
  sta pppTransmitActive
  m16
  jsr pppLcpPoll
  m8
  lda pppFrameReady
  pppLcpPollRequireNonzero @fail65
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_PROTOCOL_REJECT
  pppLcpPollRequireEqual @fail65
  jsr pppTransmitInitialize
  m16
  jsr pppLcpPoll
  m8
  lda pppFrameReady
  ora pppLcpPendingAction
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_PROTOCOL_REJECT
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 5
  cmp #$01
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 7
  cmp #$09
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 8
  cmp #$80
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 9
  cmp #$57
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 10
  cmp #$aa
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 12
  cmp #$cc
  pppLcpPollRequireEqual @fail65
  lda pppLcpRejectIdentifier
  cmp #$01
  pppLcpPollRequireEqual @fail65
  m16
  lda pppLcpLastRejectedProtocol
  cmp #$8057
  beq :+
  m8
  jmp @fail65
:
  .a16
  lda pppLcpProtocolRejectCount
  cmp #$0001
  beq :+
  m8
  jmp @fail65
:
  m8
  ; An unknown LCP Code is rejected with exactly the packet declared by its
  ; Length field. PPP padding is excluded and a busy encoder retains the frame.
  lda #$7f
  sta pppFrameBuffer + 4
  lda #$42
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #$06
  sta pppFrameBuffer + 7
  lda #$aa
  sta pppFrameBuffer + 8
  lda #$bb
  sta pppFrameBuffer + 9
  lda #$cc
  sta pppFrameBuffer + 10
  m16
  lda #PPP_PROTOCOL_LCP
  sta pppLastProtocol
  lda #$000b
  sta pppLastFrameLength
  m8
  lda #$01
  sta pppFrameReady
  sta pppTransmitActive
  m16
  jsr pppLcpPoll
  m8
  lda pppFrameReady
  pppLcpPollRequireNonzero @fail66
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CODE_REJECT
  pppLcpPollRequireEqual @fail66
  jsr pppTransmitInitialize
  m16
  jsr pppLcpPoll
  m8
  lda pppFrameReady
  ora pppLcpPendingAction
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CODE_REJECT
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 5
  cmp #$02
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 7
  cmp #$0a
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 8
  cmp #$7f
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 9
  cmp #$42
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 10
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 11
  cmp #$06
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 12
  cmp #$aa
  pppLcpPollRequireEqual @fail66
  lda pppTransmitBuffer + 13
  cmp #$bb
  pppLcpPollRequireEqual @fail66
  lda pppLcpLastRejectedCode
  cmp #$7f
  pppLcpPollRequireEqual @fail66
  lda pppLcpRejectIdentifier
  cmp #$02
  pppLcpPollRequireEqual @fail66
  m16
  lda pppLcpCodeRejectCount
  cmp #$0001
  beq :+
  m8
  jmp @fail66
:
  m8
  ; A peer request in Opened serializes its Ack before a fresh local request.
  jsr pppTransmitInitialize
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  ldx #$0008
  jsr @writeEmptyPacket
  m16
  jsr pppLcpPoll
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_SENT
  pppLcpPollRequireEqual @fail64
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CONFIGURE_ACK
  pppLcpPollRequireEqual @fail64
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_REQUEST
  pppLcpPollRequireEqual @fail64
  lda pppLcpDeferredRequest
  pppLcpPollRequireEqual @fail64

  jsr pppTransmitInitialize
  m16
  jsr pppLcpPoll
  m8
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CONFIGURE_REQUEST
  pppLcpPollRequireEqual @fail64
  lda pppTransmitBuffer + 5
  cmp #$01
  pppLcpPollRequireEqual @fail64
  lda pppLcpPendingAction
  pppLcpPollRequireEqual @fail64

  ; A peer Terminate-Request is acknowledged before LCP enters Stopped.
  jsr pppTransmitInitialize
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  lda #PPP_LCP_CODE_TERMINATE_REQUEST
  ldx #$0042
  jsr @writeEmptyPacket
  m16
  jsr pppLcpPoll
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_STOPPED
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_TERMINATE_ACK
  pppLcpPollRequireEqual @fail65
  lda pppTransmitBuffer + 5
  cmp #$42
  pppLcpPollRequireEqual @fail65
  lda pppFrameReady
  ora pppLcpPendingAction
  pppLcpPollRequireEqual @fail65
  lda pppTransmitActive
  pppLcpPollRequireNonzero @fail65

  ; Disabling ownership releases any retained frame, cancels TX, and lowers LCP.
  lda #$01
  sta pppFrameReady
  stz pppReceiveEnabled
  m16
  jsr pppLcpPoll
  m8
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSED
  pppLcpPollRequireEqual @fail65
  lda pppFrameReady
  ora pppTransmitActive
  ora pppLcpPendingAction
  ora pppLcpTimerActive
  ora pppLcpDeferredRequest
  pppLcpPollRequireEqual @fail65

  jsr @cleanup
  lda #$00
  clc
  bra @return

@fail60:
  lda #$60
  bra @fail
@fail61:
  lda #$61
  bra @fail
@fail62:
  lda #$62
  bra @fail
@fail63:
  lda #$63
  bra @fail
@fail64:
  lda #$64
  bra @fail
@fail65:
  lda #$65
  bra @fail
@fail66:
  lda #$66

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
  .a8
  lda pppLcpPollSavedModemState
  sta modemDriverState
  jsr pppReceiveInitialize
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
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
  m16
  lda #PPP_PROTOCOL_LCP
  sta pppLastProtocol
  lda #PPP_LCP_MINIMUM_FRAME_LENGTH
  sta pppLastFrameLength
  m8
  lda #$01
  sta pppFrameReady
  rts
.endproc
