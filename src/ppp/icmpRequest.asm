.include "../macro/utility.asm"
.include "constants.inc"

.code

.import frameCounter
.import pppSnapshotBegin, pppSnapshotEnd
.import pppTransmitActive, pppTransmitBuffer, pppTransmitInitialize
.import pppIpcpState, pppIpcpFlags, pppIpcpLocalAddress
.import pppIpcpInitialize
.import pppIpv4SourceAddress, pppIpv4TransmitDestination
.import pppIpv4BeginTransmit, pppIpv4Initialize
.import pppIcmpIdentifier, pppIcmpSequence, pppIcmpPayloadLength
.import pppIcmpTransmitCount, pppIcmpPacketOffset
.import pppIcmpInitialize, pppIcmpChecksumTransmitMessage
.import pppIcmpRequestState, pppIcmpRequestLastError, pppIcmpRequestFlags
.import pppIcmpRequestDestination
.import pppIcmpRequestIdentifier, pppIcmpRequestSequence
.import pppIcmpRequestDeadline, pppIcmpRequestSentFrame, pppIcmpRequestRttFrames
.import pppIcmpRequestCount, pppIcmpRequestResponseCount
.import pppIcmpRequestDropCount, pppIcmpRequestTimeoutCount
.import pppIcmpRequestTestSavedFrameCounter
.import pppFrameBuffer

.export pppIcmpRequestInitialize, pppIcmpRequestBegin
.export pppIcmpRequestPoll, pppIcmpRequestReceive
.export pppIcmpRequestRunSelfTest

.macro pppIcmpRequestFail error
  lda #PPP_ICMP_REQUEST_STATE_FAILED
  sta pppIcmpRequestState
  lda #error
  sta pppIcmpRequestLastError
  stz pppIcmpRequestFlags
  pppIncrement32 pppIcmpRequestDropCount
.endmacro

.proc pppIcmpRequestInitialize
  .a8
  .i16

  stz pppIcmpRequestState
  stz pppIcmpRequestLastError
  stz pppIcmpRequestFlags
  stz pppIcmpRequestDestination + 0
  stz pppIcmpRequestDestination + 1
  stz pppIcmpRequestDestination + 2
  stz pppIcmpRequestDestination + 3
  m16
  lda #PPP_ICMP_REQUEST_IDENTIFIER
  sta pppIcmpRequestIdentifier
  stz pppIcmpRequestSequence
  stz pppIcmpRequestDeadline
  stz pppIcmpRequestSentFrame
  stz pppIcmpRequestRttFrames
  stz pppIcmpRequestCount
  stz pppIcmpRequestCount + 2
  stz pppIcmpRequestResponseCount
  stz pppIcmpRequestResponseCount + 2
  stz pppIcmpRequestDropCount
  stz pppIcmpRequestDropCount + 2
  stz pppIcmpRequestTimeoutCount
  stz pppIcmpRequestTimeoutCount + 2
  m8
  rts
.endproc

; Queue one request to the destination already copied into
; pppIcmpRequestDestination. Carry set returns an immediate request error in A.
.proc pppIcmpRequestBegin
  .a8
  .i16

  phb
  setDBR $7e
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_REQUESTED
  beq busy
  cmp #PPP_ICMP_REQUEST_STATE_WAITING
  beq busy
  jsr pppIcmpRequestLinkIsOpen
  bcs linkClosed

  jsr pppSnapshotBegin
  lda #PPP_ICMP_REQUEST_STATE_REQUESTED
  sta pppIcmpRequestState
  stz pppIcmpRequestLastError
  stz pppIcmpRequestFlags
  m16
  lda #PPP_ICMP_REQUEST_IDENTIFIER
  sta pppIcmpRequestIdentifier
  inc pppIcmpRequestSequence
  stz pppIcmpRequestDeadline
  stz pppIcmpRequestSentFrame
  stz pppIcmpRequestRttFrames
  m8
  jsr pppSnapshotEnd
  plb
  clc
  rts

busy:
  lda #PPP_ICMP_REQUEST_ERROR_REQUEST_BUSY
  plb
  sec
  rts

linkClosed:
  jsr pppSnapshotBegin
  pppIcmpRequestFail PPP_ICMP_REQUEST_ERROR_LINK_NOT_OPEN
  jsr pppSnapshotEnd
  lda pppIcmpRequestLastError
  plb
  sec
  rts

.endproc

.proc pppIcmpRequestLinkIsOpen
  .a8
  .i16
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_OPENED
  bne closed
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_LOCAL_VALID
  beq closed
  clc
  rts
closed:
  sec
  rts
.endproc

; Wait for the shared transmitter, construct the fixed correlated Echo
; Request, and enforce a response deadline after transmission starts.
.proc pppIcmpRequestPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e
  m8
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_REQUESTED
  beq requested
  cmp #PPP_ICMP_REQUEST_STATE_WAITING
  bne :+
  jmp waiting
:
  jmp done

requested:
  jsr pppIcmpRequestLinkIsOpen
  bcc :+
  jmp linkClosed
:
  lda pppTransmitActive
  beq build
  jmp done

build:
  ldx #$0000
copyDestination:
  lda pppIcmpRequestDestination, x
  sta pppIpv4TransmitDestination, x
  inx
  cpx #$0004
  bne copyDestination

  lda #PPP_ICMP_TYPE_ECHO_REQUEST
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 0
  stz pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 1
  stz pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 2
  stz pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 3
  m16
  lda pppIcmpRequestIdentifier
  xba
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 4
  lda pppIcmpRequestSequence
  xba
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 6
  m8
  lda #'N'
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 8
  lda #'D'
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 9
  lda #'M'
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 10
  lda #'2'
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 11
  lda #'4'
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12

  m16
  ldx #(PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH)
  lda #PPP_ICMP_REQUEST_MESSAGE_LENGTH
  jsr pppIcmpChecksumTransmitMessage
  eor #$ffff
  xba
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 2

  ldx #PPP_ICMP_REQUEST_MESSAGE_LENGTH
  m8
  lda #PPP_IPV4_PROTOCOL_ICMP
  jsr pppIpv4BeginTransmit
  bcs transmitFailed

  jsr pppSnapshotBegin
  lda #PPP_ICMP_REQUEST_STATE_WAITING
  sta pppIcmpRequestState
  stz pppIcmpRequestLastError
  stz pppIcmpRequestFlags
  pppIncrement32 pppIcmpRequestCount
  pppIncrement32 pppIcmpTransmitCount
  m16
  lda frameCounter
  sta pppIcmpRequestSentFrame
  clc
  adc #PPP_ICMP_REQUEST_TIMEOUT_FRAMES
  sta pppIcmpRequestDeadline
  m8
  jsr pppSnapshotEnd
  jmp done

transmitFailed:
  jsr pppSnapshotBegin
  pppIcmpRequestFail PPP_ICMP_REQUEST_ERROR_TRANSMIT_FAILED
  jsr pppSnapshotEnd
  bra done

waiting:
  jsr pppIcmpRequestLinkIsOpen
  bcs linkClosed
  m16
  lda frameCounter
  sec
  sbc pppIcmpRequestDeadline
  bmi done16
  m8
  jsr pppSnapshotBegin
  pppIcmpRequestFail PPP_ICMP_REQUEST_ERROR_TIMEOUT
  pppIncrement32 pppIcmpRequestTimeoutCount
  jsr pppSnapshotEnd
  bra done

linkClosed:
  jsr pppSnapshotBegin
  pppIcmpRequestFail PPP_ICMP_REQUEST_ERROR_LINK_NOT_OPEN
  jsr pppSnapshotEnd
  bra done

done16:
  m8
done:
  mi16
  ply
  plx
  plb
  pla
  rts
.endproc

; Correlate an already checksum-validated Echo Reply. Candidate mismatches are
; counted but leave the live request waiting for its valid response.
.proc pppIcmpRequestReceive
  .a8
  .i16

  phb
  phx
  setDBR $7e
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_WAITING
  beq :+
  jmp done
:
  jsr pppSnapshotBegin

  ldx #$0000
source:
  lda pppIpv4SourceAddress, x
  cmp pppIcmpRequestDestination, x
  beq :+
  jmp sourceMismatch
:
  inx
  cpx #$0004
  bne source

  m16
  lda pppIcmpIdentifier
  cmp pppIcmpRequestIdentifier
  bne identifierMismatch16
  lda pppIcmpSequence
  cmp pppIcmpRequestSequence
  bne sequenceMismatch16
  lda pppIcmpPayloadLength
  cmp #PPP_ICMP_REQUEST_PAYLOAD_LENGTH
  bne payloadMismatch16

  lda pppIcmpPacketOffset
  clc
  adc #PPP_ICMP_ECHO_HEADER_LENGTH
  tax
  m8
  lda pppFrameBuffer + 0, x
  cmp #'N'
  bne payloadMismatch
  lda pppFrameBuffer + 1, x
  cmp #'D'
  bne payloadMismatch
  lda pppFrameBuffer + 2, x
  cmp #'M'
  bne payloadMismatch
  lda pppFrameBuffer + 3, x
  cmp #'2'
  bne payloadMismatch
  lda pppFrameBuffer + 4, x
  cmp #'4'
  bne payloadMismatch

  lda #PPP_ICMP_REQUEST_STATE_RECEIVED
  sta pppIcmpRequestState
  stz pppIcmpRequestLastError
  lda #PPP_ICMP_REQUEST_FLAG_RESPONSE_VALID
  sta pppIcmpRequestFlags
  pppIncrement32 pppIcmpRequestResponseCount
  m16
  lda frameCounter
  sec
  sbc pppIcmpRequestSentFrame
  sta pppIcmpRequestRttFrames
  m8
  bra finish

identifierMismatch16:
  m8
  lda #PPP_ICMP_REQUEST_ERROR_IDENTIFIER_MISMATCH
  bra reject
sequenceMismatch16:
  m8
  lda #PPP_ICMP_REQUEST_ERROR_SEQUENCE_MISMATCH
  bra reject
payloadMismatch16:
  m8
payloadMismatch:
  lda #PPP_ICMP_REQUEST_ERROR_PAYLOAD_MISMATCH
  bra reject
sourceMismatch:
  lda #PPP_ICMP_REQUEST_ERROR_SOURCE_MISMATCH
reject:
  sta pppIcmpRequestLastError
  pppIncrement32 pppIcmpRequestDropCount
finish:
  jsr pppSnapshotEnd
done:
  plx
  plb
  clc
  rts
.endproc

.macro pppIcmpRequestRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; Backpressure, correlation, mismatch, timeout, and link-gating fixtures.
; Failure steps $a2-$a7 are reserved for outbound ICMP Echo.
.proc pppIcmpRequestRunSelfTest
  .a8
  .i16

  sep #$20
  rep #$10
  phb
  phx
  phy
  setDBR $7e
  m16
  lda frameCounter
  sta pppIcmpRequestTestSavedFrameCounter
  lda frameCounter + 2
  sta pppIcmpRequestTestSavedFrameCounter + 2
  m8
  jsr prepareLink
  jsr setDestination
  jsr pppIcmpRequestBegin
  bcc :+
  jmp faila2
:
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_REQUESTED
  pppIcmpRequestRequireEqual faila2
  m16
  lda pppIcmpRequestSequence
  cmp #$0001
  pppIcmpRequestRequireEqual faila2_16
  m8
  ; A busy transmitter must leave the request queued without consuming it.
  lda #$01
  sta pppTransmitActive
  m16
  jsr pppIcmpRequestPoll
  m8
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_REQUESTED
  pppIcmpRequestRequireEqual faila3

  jsr pppTransmitInitialize
  m16
  lda #$0100
  sta frameCounter
  jsr pppIcmpRequestPoll
  m8
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_WAITING
  pppIcmpRequestRequireEqual faila4
  lda pppTransmitActive
  cmp #$01
  pppIcmpRequestRequireEqual faila4
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 0
  cmp #PPP_ICMP_TYPE_ECHO_REQUEST
  pppIcmpRequestRequireEqual faila4
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 4
  cmp #$4e
  pppIcmpRequestRequireEqual faila4
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 5
  cmp #$44
  pppIcmpRequestRequireEqual faila4
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12
  cmp #'4'
  pppIcmpRequestRequireEqual faila4
  lda pppIpv4TransmitDestination + 0
  cmp #$01
  pppIcmpRequestRequireEqual faila4
  m16
  lda pppIcmpRequestCount
  cmp #$0001
  pppIcmpRequestRequireEqual faila4_16
  m8
  jsr prepareReply
  m16
  lda #$0107
  sta frameCounter
  m8
  jsr pppIcmpRequestReceive
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_RECEIVED
  pppIcmpRequestRequireEqual faila5
  lda pppIcmpRequestFlags
  cmp #PPP_ICMP_REQUEST_FLAG_RESPONSE_VALID
  pppIcmpRequestRequireEqual faila5
  m16
  lda pppIcmpRequestRttFrames
  cmp #$0007
  pppIcmpRequestRequireEqual faila5_16
  lda pppIcmpRequestResponseCount
  cmp #$0001
  pppIcmpRequestRequireEqual faila5_16
  m8
  ; Reject a wrong source without consuming the in-flight second request.
  jsr pppTransmitInitialize
  jsr pppIcmpRequestBegin
  bcc :+
  jmp faila6
:
  m16
  jsr pppIcmpRequestPoll
  m8
  jsr prepareReply
  inc pppIpv4SourceAddress + 3
  jsr pppIcmpRequestReceive
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_WAITING
  pppIcmpRequestRequireEqual faila6
  lda pppIcmpRequestLastError
  cmp #PPP_ICMP_REQUEST_ERROR_SOURCE_MISMATCH
  pppIcmpRequestRequireEqual faila6

  ; Let a third request reach its exact modular deadline.
  jsr pppIcmpInitialize
  jsr prepareLink
  jsr setDestination
  jsr pppIcmpRequestBegin
  bcs faila7
  m16
  jsr pppIcmpRequestPoll
  lda pppIcmpRequestDeadline
  sta frameCounter
  jsr pppIcmpRequestPoll
  m8
  lda pppIcmpRequestState
  cmp #PPP_ICMP_REQUEST_STATE_FAILED
  pppIcmpRequestRequireEqual faila7
  lda pppIcmpRequestLastError
  cmp #PPP_ICMP_REQUEST_ERROR_TIMEOUT
  pppIcmpRequestRequireEqual faila7
  m16
  lda pppIcmpRequestTimeoutCount
  cmp #$0001
  pppIcmpRequestRequireEqual faila7_16

  jsr cleanup
  m8
  lda #$00
  clc
  bra return

faila2_16:
  m8
faila2:
  lda #$a2
  bra fail
faila3:
  lda #$a3
  bra fail
faila4_16:
  m8
faila4:
  lda #$a4
  bra fail
faila5_16:
  m8
faila5:
  lda #$a5
  bra fail
faila6:
  lda #$a6
  bra fail
faila7_16:
  m8
faila7:
  lda #$a7
fail:
  pha
  m16
  jsr cleanup
  m8
  pla
  sec
return:
  ply
  plx
  plb
  rts

prepareLink:
  assert_m8_i16
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppIcmpInitialize
  lda #PPP_IPCP_STATE_OPENED
  sta pppIpcpState
  lda #PPP_IPCP_FLAG_LOCAL_VALID
  sta pppIpcpFlags
  lda #$0a
  sta pppIpcpLocalAddress + 0
  lda #$18
  sta pppIpcpLocalAddress + 1
  stz pppIpcpLocalAddress + 2
  lda #$02
  sta pppIpcpLocalAddress + 3
  rts

setDestination:
  assert_m8_i16
  lda #$01
  sta pppIcmpRequestDestination + 0
  sta pppIcmpRequestDestination + 1
  sta pppIcmpRequestDestination + 2
  sta pppIcmpRequestDestination + 3
  rts

prepareReply:
  assert_m8_i16
  ldx #$0000
:
  lda pppIcmpRequestDestination, x
  sta pppIpv4SourceAddress, x
  inx
  cpx #$0004
  bne :-
  m16
  lda pppIcmpRequestIdentifier
  sta pppIcmpIdentifier
  lda pppIcmpRequestSequence
  sta pppIcmpSequence
  lda #PPP_ICMP_REQUEST_PAYLOAD_LENGTH
  sta pppIcmpPayloadLength
  lda #(PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH)
  sta pppIcmpPacketOffset
  tax
  m8
  lda #'N'
  sta pppFrameBuffer + PPP_ICMP_ECHO_HEADER_LENGTH + 0, x
  lda #'D'
  sta pppFrameBuffer + PPP_ICMP_ECHO_HEADER_LENGTH + 1, x
  lda #'M'
  sta pppFrameBuffer + PPP_ICMP_ECHO_HEADER_LENGTH + 2, x
  lda #'2'
  sta pppFrameBuffer + PPP_ICMP_ECHO_HEADER_LENGTH + 3, x
  lda #'4'
  sta pppFrameBuffer + PPP_ICMP_ECHO_HEADER_LENGTH + 4, x
  rts

cleanup:
  assert_m16_i16
  lda pppIcmpRequestTestSavedFrameCounter
  sta frameCounter
  lda pppIcmpRequestTestSavedFrameCounter + 2
  sta frameCounter + 2
  m8
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppIcmpInitialize
  m16
  rts
.endproc
