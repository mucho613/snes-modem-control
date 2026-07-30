.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import modemDriverState
.import pppReceiveEnabled, pppFrameReady, pppReleaseFrame
.import pppReceiveInitialize
.import pppTransmitActive, pppTransmitBuffer
.import pppTransmitAbort, pppTransmitInitialize
.import pppLcpState, pppPapState
.import pppLcpInitialize, pppPapInitialize
.import pppLastProtocol, pppLastFrameLength, pppFrameBuffer
.import pppIpcpState, pppIpcpPendingAction, pppIpcpDeferredRequest
.import pppIpcpPollAction, pppIpcpPollSavedModemState
.import pppIpcpLocalAddress, pppIpcpPeerAddress
.import pppIpcpInitialize
.import pppIpcpLowerUp, pppIpcpLowerDown
.import pppIpcpReceiveFrame, pppIpcpBuildPending, pppIpcpPollTimeout

.export pppIpcpPoll, pppIpcpPollRunSelfTest

; Run after PAP polling. IPCP owns protocol $8021 frames only after PAP is
; Opened, and serializes all responses through the shared PPP encoder.
.proc pppIpcpPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e
  sep #$20
  .a8

  lda pppReceiveEnabled
  beq @lowerDown
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  bne @lowerDown
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  bne @lowerDown
  lda pppPapState
  cmp #PPP_PAP_STATE_OPENED
  bne @lowerDown

  lda pppIpcpState
  cmp #PPP_IPCP_STATE_CLOSED
  beq @open
  cmp #PPP_IPCP_STATE_STOPPED
  beq @stopped

@service:
  jsr @servicePending
  bcc :+
  jmp @done
:
  lda pppFrameReady
  beq @timer
  rep #$20
  .a16
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_IPCP
  beq @receiveIpcp
  cmp #PPP_PROTOCOL_IP
  beq @done
  sep #$20
  .a8
  ; Unknown network protocols have no later consumer.
  jsr pppReleaseFrame
  bra @timer

@open:
  .a8
  jsr pppIpcpLowerUp
  bra @service

@stopped:
  lda pppFrameReady
  beq @done
  jsr pppReleaseFrame
  bra @done

@receiveIpcp:
  sep #$20
  .a8
  jsr pppIpcpReceiveFrame
  bcs @release
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_ACK
  beq @responsePending
  cmp #PPP_IPCP_ACTION_CONFIGURE_NAK
  beq @responsePending
  cmp #PPP_IPCP_ACTION_CONFIGURE_REJECT
  beq @responsePending
@release:
  jsr pppReleaseFrame
  jsr @servicePending
  bra @timer

@responsePending:
  jsr @servicePending
  bcs @done

@timer:
  jsr pppIpcpPollTimeout
  jsr @servicePending
  bra @done

@lowerDown:
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_CLOSED
  beq @done
  lda pppFrameReady
  beq :+
  jsr pppReleaseFrame
:
  jsr pppIpcpLowerDown
  lda pppReceiveEnabled
  beq @abortTransmit
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  bne @abortTransmit

  ; A peer LCP Terminate-Request can lower IPCP after its Terminate-Ack has
  ; already entered the shared encoder. Preserve only that LCP response;
  ; any IPCP-owned frame still belongs to the layer being lowered.
  lda pppTransmitActive
  beq @done
  lda pppTransmitBuffer + 2
  cmp #$c0
  bne @abortTransmit
  lda pppTransmitBuffer + 3
  cmp #$21
  bne @abortTransmit
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_TERMINATE_ACK
  beq @done
@abortTransmit:
  jsr pppTransmitAbort

@done:
  rep #$30
  .a16
  .i16
  ply
  plx
  plb
  pla
  rts

; Carry set means encoder backpressure. Response packets retain the receive
; frame until accepted; a renegotiation request is then promoted.
@servicePending:
  .a8
  lda pppIpcpPendingAction
  beq @ready
  sta pppIpcpPollAction
  jsr pppIpcpBuildPending
  bcs @busy
  lda pppIpcpPollAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_ACK
  beq @responseSent
  cmp #PPP_IPCP_ACTION_CONFIGURE_NAK
  beq @responseSent
  cmp #PPP_IPCP_ACTION_CONFIGURE_REJECT
  bne @ready
@responseSent:
  lda pppFrameReady
  beq :+
  jsr pppReleaseFrame
:
  lda pppIpcpDeferredRequest
  beq @ready
  stz pppIpcpDeferredRequest
  lda #PPP_IPCP_ACTION_CONFIGURE_REQUEST
  sta pppIpcpPendingAction
@ready:
  clc
  rts
@busy:
  sec
  rts
.endproc

.macro pppIpcpPollRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; Deterministic main-loop integration test. It verifies phase gating, receive
; ownership under encoder backpressure, response release, and lower-down.
; Failure steps $77-$79 are reserved for IPCP polling.
.proc pppIpcpPollRunSelfTest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  lda modemDriverState
  sta pppIpcpPollSavedModemState
  jsr pppReceiveInitialize
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
  jsr pppPapInitialize
  jsr pppIpcpInitialize
  lda #MODEM_STATE_CONNECTED
  sta modemDriverState
  lda #$01
  sta pppReceiveEnabled
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  lda #PPP_PAP_STATE_OPENED
  sta pppPapState

  ; The first eligible poll opens IPCP and submits its local request.
  rep #$20
  .a16
  jsr pppIpcpPoll
  sep #$20
  .a8
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_REQUEST_SENT
  pppIpcpPollRequireEqual @fail77
  lda pppTransmitActive
  bne :+
  jmp @fail77
:

  ; A peer request remains owned while that local request occupies TX.
  lda #PPP_IPCP_CODE_CONFIGURE_REQUEST
  sta pppFrameBuffer + 4
  lda #$11
  sta pppFrameBuffer + 5
  stz pppFrameBuffer + 6
  lda #PPP_IPCP_ADDRESS_CONFIGURE_PACKET_LENGTH
  sta pppFrameBuffer + 7
  lda #PPP_IPCP_OPTION_IP_ADDRESS
  sta pppFrameBuffer + 8
  lda #PPP_IPCP_IP_ADDRESS_OPTION_LENGTH
  sta pppFrameBuffer + 9
  lda #PPP_IPCP_PEER_ADDRESS_0
  sta pppFrameBuffer + 10
  lda #PPP_IPCP_PEER_ADDRESS_1
  sta pppFrameBuffer + 11
  lda #PPP_IPCP_PEER_ADDRESS_2
  sta pppFrameBuffer + 12
  lda #PPP_IPCP_PEER_ADDRESS_3
  sta pppFrameBuffer + 13
  rep #$20
  .a16
  lda #PPP_PROTOCOL_IPCP
  sta pppLastProtocol
  lda #PPP_IPCP_ADDRESS_CONFIGURE_FRAME_LENGTH
  sta pppLastFrameLength
  sep #$20
  .a8
  lda #$01
  sta pppFrameReady
  rep #$20
  .a16
  jsr pppIpcpPoll
  sep #$20
  .a8
  lda pppIpcpPendingAction
  cmp #PPP_IPCP_ACTION_CONFIGURE_ACK
  pppIpcpPollRequireEqual @fail78
  lda pppFrameReady
  bne :+
  jmp @fail78
:

  ; Once TX is idle the Ack is submitted and the retained frame is released.
  jsr pppTransmitInitialize
  rep #$20
  .a16
  jsr pppIpcpPoll
  sep #$20
  .a8
  lda pppFrameReady
  ora pppIpcpPendingAction
  pppIpcpPollRequireEqual @fail78
  lda pppTransmitBuffer + 4
  cmp #PPP_IPCP_CODE_CONFIGURE_ACK
  pppIpcpPollRequireEqual @fail78
  lda pppIpcpPeerAddress + 3
  cmp #PPP_IPCP_PEER_ADDRESS_3
  pppIpcpPollRequireEqual @fail78

  ; Losing the PAP upper layer lowers IPCP and aborts its active response.
  stz pppPapState
  rep #$20
  .a16
  jsr pppIpcpPoll
  sep #$20
  .a8
  lda pppIpcpState
  pppIpcpPollRequireEqual @fail79
  lda pppTransmitActive
  ora pppIpcpPendingAction
  ora pppIpcpDeferredRequest
  pppIpcpPollRequireEqual @fail79

  jsr @cleanup
  lda #$00
  clc
  bra @return
@fail77:
  lda #$77
  bra @fail
@fail78:
  lda #$78
  bra @fail
@fail79:
  lda #$79
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
  lda pppIpcpPollSavedModemState
  sta modemDriverState
  jsr pppReceiveInitialize
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
  jsr pppPapInitialize
  jsr pppIpcpInitialize
  rts
.endproc
