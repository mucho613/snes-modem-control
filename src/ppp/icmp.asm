.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppSnapshotBegin, pppSnapshotEnd
.import pppFrameBuffer, pppTransmitActive, pppTransmitBuffer
.import pppTransmitInitialize
.import pppIpcpState, pppIpcpFlags, pppIpcpLocalAddress
.import pppIpcpInitialize
.import pppIpv4HeaderLength, pppIpv4Protocol, pppIpv4PayloadLength
.import pppIpv4SourceAddress
.import pppIpv4TransmitDestination, pppIpv4BeginTransmit
.import pppIpv4TransmitCount, pppIpv4Initialize
.import pppIcmpLastError, pppIcmpLastType, pppIcmpLastCode, pppIcmpFlags
.import pppIcmpIdentifier, pppIcmpSequence, pppIcmpPayloadLength
.import pppIcmpChecksum, pppIcmpReceiveCount, pppIcmpEchoRequestCount
.import pppIcmpEchoReplyCount, pppIcmpChecksumErrorCount
.import pppIcmpDropCount, pppIcmpTransmitCount
.import pppIcmpInboundState, pppIcmpInboundLastError, pppIcmpInboundFlags
.import pppIcmpInboundSource
.import pppIcmpInboundIdentifier, pppIcmpInboundSequence, pppIcmpInboundPayloadLength
.import pppIcmpInboundReplyCount, pppIcmpInboundDropCount
.import pppIcmpPacketOffset, pppIcmpChecksumAccumulator
.import pppIcmpRequestInitialize, pppIcmpRequestReceive

.export pppIcmpInitialize, pppIcmpReceive
.export pppIcmpRetryPending, pppIcmpCancelPending
.export pppIcmpChecksumTransmitMessage
.export pppIcmpRunSelfTest

.macro pppIcmpReceiveError error
  .local notInbound
  lda pppIcmpLastType
  cmp #PPP_ICMP_TYPE_ECHO_REQUEST
  bne notInbound
  lda #PPP_ICMP_INBOUND_STATE_FAILED
  sta pppIcmpInboundState
  lda #error
  sta pppIcmpInboundLastError
  pppIncrement32 pppIcmpInboundDropCount
notInbound:
  lda #error
  sta pppIcmpLastError
  pppIncrement32 pppIcmpDropCount
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts
.endmacro

.proc pppIcmpInitialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppIcmpLastError
  stz pppIcmpLastType
  stz pppIcmpLastCode
  stz pppIcmpFlags
  stz pppIcmpInboundState
  stz pppIcmpInboundLastError
  stz pppIcmpInboundFlags
  stz pppIcmpInboundSource + 0
  stz pppIcmpInboundSource + 1
  stz pppIcmpInboundSource + 2
  stz pppIcmpInboundSource + 3
  m16
  stz pppIcmpIdentifier
  stz pppIcmpSequence
  stz pppIcmpPayloadLength
  stz pppIcmpChecksum
  stz pppIcmpReceiveCount
  stz pppIcmpReceiveCount + 2
  stz pppIcmpEchoRequestCount
  stz pppIcmpEchoRequestCount + 2
  stz pppIcmpEchoReplyCount
  stz pppIcmpEchoReplyCount + 2
  stz pppIcmpChecksumErrorCount
  stz pppIcmpChecksumErrorCount + 2
  stz pppIcmpDropCount
  stz pppIcmpDropCount + 2
  stz pppIcmpTransmitCount
  stz pppIcmpTransmitCount + 2
  stz pppIcmpInboundIdentifier
  stz pppIcmpInboundSequence
  stz pppIcmpInboundPayloadLength
  stz pppIcmpInboundReplyCount
  stz pppIcmpInboundReplyCount + 2
  stz pppIcmpInboundDropCount
  stz pppIcmpInboundDropCount + 2
  stz pppIcmpPacketOffset
  stz pppIcmpChecksumAccumulator
  m8
  jsr pppIcmpRequestInitialize
  plb
  rts
.endproc

; Parse an ICMP Echo message from the current, already validated local IPv4
; packet. Carry set means the Echo Request remains owned while the single PPP
; transmitter is busy; carry clear means the caller may release the frame.
.proc pppIcmpReceive
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppSnapshotBegin
  pppIncrement32 pppIcmpReceiveCount
  stz pppIcmpLastError
  stz pppIcmpLastType
  stz pppIcmpLastCode
  stz pppIcmpFlags
  m16
  stz pppIcmpIdentifier
  stz pppIcmpSequence
  stz pppIcmpPayloadLength
  stz pppIcmpChecksum

  lda pppIpv4PayloadLength
  cmp #PPP_ICMP_ECHO_HEADER_LENGTH
  bcs packetOffset
  m8
  pppIcmpReceiveError PPP_ICMP_ERROR_TRUNCATED

packetOffset:
  m8
  lda pppIpv4HeaderLength
  m16
  and #$00ff
  clc
  adc #PPP_IPV4_FRAME_OFFSET
  sta pppIcmpPacketOffset
  tax
  m8
  lda pppFrameBuffer + 0, x
  sta pppIcmpLastType
  cmp #PPP_ICMP_TYPE_ECHO_REQUEST
  beq readCode
  cmp #PPP_ICMP_TYPE_ECHO_REPLY
  beq readCode
  pppIcmpReceiveError PPP_ICMP_ERROR_UNSUPPORTED_TYPE

readCode:
  lda pppFrameBuffer + 1, x
  sta pppIcmpLastCode
  beq readFields
  pppIcmpReceiveError PPP_ICMP_ERROR_NONZERO_CODE

readFields:
  m16
  lda pppFrameBuffer + 2, x
  xba
  sta pppIcmpChecksum
  lda pppFrameBuffer + 4, x
  xba
  sta pppIcmpIdentifier
  lda pppFrameBuffer + 6, x
  xba
  sta pppIcmpSequence
  lda pppIpv4PayloadLength
  sec
  sbc #PPP_ICMP_ECHO_HEADER_LENGTH
  sta pppIcmpPayloadLength

  ldx pppIcmpPacketOffset
  jsr checksumReceiveMessage
  cmp #$ffff
  beq valid
  m8
  pppIncrement32 pppIcmpChecksumErrorCount
  pppIcmpReceiveError PPP_ICMP_ERROR_INVALID_CHECKSUM

valid:
  m8
  lda pppIcmpLastType
  cmp #PPP_ICMP_TYPE_ECHO_REQUEST
  beq request
  lda #(PPP_ICMP_FLAG_VALID | PPP_ICMP_FLAG_ECHO_REPLY)
  sta pppIcmpFlags
  pppIncrement32 pppIcmpEchoReplyCount
  jsr pppIcmpRequestReceive
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

request:
  lda #(PPP_ICMP_FLAG_VALID | PPP_ICMP_FLAG_ECHO_REQUEST)
  sta pppIcmpFlags
  lda #PPP_ICMP_INBOUND_STATE_RECEIVED
  sta pppIcmpInboundState
  stz pppIcmpInboundLastError
  lda #PPP_ICMP_INBOUND_FLAG_VALID
  sta pppIcmpInboundFlags
  ldx #$0000
copyInboundSource:
  lda pppIpv4SourceAddress, x
  sta pppIcmpInboundSource, x
  inx
  cpx #$0004
  bne copyInboundSource
  m16
  lda pppIcmpIdentifier
  sta pppIcmpInboundIdentifier
  lda pppIcmpSequence
  sta pppIcmpInboundSequence
  lda pppIcmpPayloadLength
  sta pppIcmpInboundPayloadLength
  m8
  pppIncrement32 pppIcmpEchoRequestCount
  lda pppTransmitActive
  beq transmitReply
  lda pppIcmpFlags
  ora #PPP_ICMP_FLAG_REPLY_PENDING
  sta pppIcmpFlags
  jsr pppSnapshotEnd
  ply
  plx
  plb
  sec
  rts

transmitReply:
  jsr buildEchoReply
  bcc receiveDone
  lda #PPP_ICMP_ERROR_TRANSMIT_FAILED
  sta pppIcmpLastError
  sta pppIcmpInboundLastError
  lda #PPP_ICMP_INBOUND_STATE_FAILED
  sta pppIcmpInboundState
  pppIncrement32 pppIcmpDropCount
  pppIncrement32 pppIcmpInboundDropCount
receiveDone:
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

; X is the ICMP message offset in pppFrameBuffer. Returns the folded sum in
; A16, treating an odd final byte as the high byte of a zero-padded word.
checksumReceiveMessage:
  .a16
  .i16
  stz pppIcmpChecksumAccumulator
  lda pppIpv4PayloadLength
  lsr
  tay
checksumReceiveWord:
  lda pppFrameBuffer, x
  xba
  clc
  adc pppIcmpChecksumAccumulator
  sta pppIcmpChecksumAccumulator
  bcc :+
  inc pppIcmpChecksumAccumulator
:
  inx
  inx
  dey
  bne checksumReceiveWord

  lda pppIpv4PayloadLength
  and #$0001
  beq checksumReceiveDone
  m8
  lda pppFrameBuffer, x
  m16
  and #$00ff
  xba
  clc
  adc pppIcmpChecksumAccumulator
  sta pppIcmpChecksumAccumulator
  bcc checksumReceiveDone
  inc pppIcmpChecksumAccumulator
checksumReceiveDone:
  lda pppIcmpChecksumAccumulator
  rts
.endproc

; Retry a validated Echo Request retained in pppFrameBuffer. Carry remains set
; only while the shared transmitter is still busy.
.proc pppIcmpRetryPending
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  lda pppIcmpFlags
  and #PPP_ICMP_FLAG_REPLY_PENDING
  beq notPending
  lda pppTransmitActive
  beq retry
  ply
  plx
  plb
  sec
  rts

retry:
  jsr pppSnapshotBegin
  jsr buildEchoReply
  bcc retryDone
  lda pppIcmpFlags
  and #($ff ^ PPP_ICMP_FLAG_REPLY_PENDING)
  sta pppIcmpFlags
  lda #PPP_ICMP_ERROR_TRANSMIT_FAILED
  sta pppIcmpLastError
  sta pppIcmpInboundLastError
  lda #PPP_ICMP_INBOUND_STATE_FAILED
  sta pppIcmpInboundState
  pppIncrement32 pppIcmpDropCount
  pppIncrement32 pppIcmpInboundDropCount
retryDone:
  jsr pppSnapshotEnd
notPending:
  ply
  plx
  plb
  clc
  rts
.endproc

; Cancel a retained reply when the PPP link is no longer in a state where the
; corresponding receive frame can remain owned.
.proc pppIcmpCancelPending
  .a8
  .i16

  phb
  setDBR $7e
  lda pppIcmpFlags
  and #PPP_ICMP_FLAG_REPLY_PENDING
  beq done
  jsr pppSnapshotBegin
  lda pppIcmpFlags
  and #($ff ^ PPP_ICMP_FLAG_REPLY_PENDING)
  sta pppIcmpFlags
  lda #PPP_ICMP_ERROR_PENDING_ABORTED
  sta pppIcmpLastError
  sta pppIcmpInboundLastError
  lda #PPP_ICMP_INBOUND_STATE_FAILED
  sta pppIcmpInboundState
  pppIncrement32 pppIcmpDropCount
  pppIncrement32 pppIcmpInboundDropCount
  jsr pppSnapshotEnd
done:
  plb
  rts
.endproc

; Copy the retained ICMP message, convert it to an Echo Reply, calculate its
; checksum, and submit the surrounding IPv4 packet. Caller guarantees that the
; shared transmitter is idle. Carry mirrors pppIpv4BeginTransmit.
.proc buildEchoReply
  .a8
  .i16

  ldx #$0000
  ldy pppIcmpPacketOffset
copyMessage:
  lda pppFrameBuffer, y
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH, x
  inx
  iny
  cpx pppIpv4PayloadLength
  bne copyMessage

  lda #PPP_ICMP_TYPE_ECHO_REPLY
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 0
  stz pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 2
  stz pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 3

  m16
  ldx #(PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH)
  lda pppIpv4PayloadLength
  jsr pppIcmpChecksumTransmitMessage
  eor #$ffff
  xba
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 2
  m8
  ldx #$0000
copyDestination:
  lda pppIpv4SourceAddress, x
  sta pppIpv4TransmitDestination, x
  inx
  cpx #$0004
  bne copyDestination

  ldx pppIpv4PayloadLength
  lda #PPP_IPV4_PROTOCOL_ICMP
  jsr pppIpv4BeginTransmit
  bcs transmitFailed
  lda pppIcmpFlags
  and #($ff ^ PPP_ICMP_FLAG_REPLY_PENDING)
  sta pppIcmpFlags
  stz pppIcmpLastError
  pppIncrement32 pppIcmpTransmitCount
  pppIncrement32 pppIcmpInboundReplyCount
  clc
  rts
transmitFailed:
  sec
  rts
.endproc

; Calculate the checksum of the transmit-buffer ICMP message at X. A16 is the
; message length. The returned A16 is the folded, non-complemented sum.
.proc pppIcmpChecksumTransmitMessage
  .a16
  .i16
  pha
  stz pppIcmpChecksumAccumulator
  lsr
  tay
@word:
  lda pppTransmitBuffer, x
  xba
  clc
  adc pppIcmpChecksumAccumulator
  sta pppIcmpChecksumAccumulator
  bcc :+
  inc pppIcmpChecksumAccumulator
:
  inx
  inx
  dey
  bne @word

  pla
  and #$0001
  beq @done
  m8
  lda pppTransmitBuffer, x
  m16
  and #$00ff
  xba
  clc
  adc pppIcmpChecksumAccumulator
  sta pppIcmpChecksumAccumulator
  bcc @done
  inc pppIcmpChecksumAccumulator
@done:
  lda pppIcmpChecksumAccumulator
  rts
.endproc

.macro pppIcmpRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; Fixed odd-length Echo vectors and backpressure behavior. Failure steps
; $88-$8c are reserved for ICMP.
.proc pppIcmpRunSelfTest
  .a8
  .i16

  sep #$20
  rep #$10
  phb
  phx
  phy
  setDBR $7e
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppIcmpInitialize
  lda #PPP_IPCP_STATE_OPENED
  sta pppIpcpState
  lda #PPP_IPCP_FLAG_LOCAL_VALID
  sta pppIpcpFlags
  lda #$c0
  sta pppIpcpLocalAddress + 0
  lda #$a8
  sta pppIpcpLocalAddress + 1
  stz pppIpcpLocalAddress + 2
  lda #$c7
  sta pppIpcpLocalAddress + 3
  jsr prepareRequest

  jsr pppIcmpReceive
  bcc :+
  jmp fail88
:
  lda pppIcmpLastError
  pppIcmpRequireEqual fail88
  lda pppIcmpFlags
  cmp #(PPP_ICMP_FLAG_VALID | PPP_ICMP_FLAG_ECHO_REQUEST)
  pppIcmpRequireEqual fail88
  lda pppIcmpInboundState
  cmp #PPP_ICMP_INBOUND_STATE_RECEIVED
  pppIcmpRequireEqual fail88
  lda pppIcmpInboundFlags
  cmp #PPP_ICMP_INBOUND_FLAG_VALID
  pppIcmpRequireEqual fail88
  lda pppIcmpInboundSource + 3
  cmp #$01
  pppIcmpRequireEqual fail88
  m16
  lda pppIcmpIdentifier
  cmp #$1234
  pppIcmpRequireEqual fail88_16
  lda pppIcmpSequence
  cmp #$0001
  pppIcmpRequireEqual fail88_16
  lda pppIcmpPayloadLength
  cmp #$0005
  pppIcmpRequireEqual fail88_16
  lda pppIcmpReceiveCount
  cmp #$0001
  pppIcmpRequireEqual fail88_16
  lda pppIcmpEchoRequestCount
  cmp #$0001
  pppIcmpRequireEqual fail88_16
  lda pppIcmpInboundIdentifier
  cmp #$1234
  pppIcmpRequireEqual fail88_16
  lda pppIcmpInboundSequence
  cmp #$0001
  pppIcmpRequireEqual fail88_16
  lda pppIcmpInboundPayloadLength
  cmp #$0005
  pppIcmpRequireEqual fail88_16
  m8
  lda pppTransmitActive
  cmp #$01
  pppIcmpRequireEqual fail89
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 0
  pppIcmpRequireEqual fail89
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 2
  cmp #$1e
  pppIcmpRequireEqual fail89
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 3
  cmp #$54
  pppIcmpRequireEqual fail89
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 8
  cmp #$4e
  pppIcmpRequireEqual fail89
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12
  cmp #$34
  pppIcmpRequireEqual fail89
  lda pppIpv4TransmitDestination + 3
  cmp #$01
  pppIcmpRequireEqual fail89
  m16
  lda pppIcmpTransmitCount
  cmp #$0001
  pppIcmpRequireEqual fail89_16
  lda pppIpv4TransmitCount
  cmp #$0001
  pppIcmpRequireEqual fail89_16
  lda pppIcmpInboundReplyCount
  cmp #$0001
  pppIcmpRequireEqual fail89_16
  m8
  ; The active first reply forces a second request to remain owned.
  jsr pppIcmpReceive
  bcs :+
  jmp fail8a
:
  lda pppIcmpFlags
  cmp #(PPP_ICMP_FLAG_VALID | PPP_ICMP_FLAG_ECHO_REQUEST | PPP_ICMP_FLAG_REPLY_PENDING)
  pppIcmpRequireEqual fail8a
  jsr pppIcmpRetryPending
  bcs :+
  jmp fail8a
:

  ; Once the shared transmitter becomes idle, the retained request is sent
  ; without being counted as a third receive.
  jsr pppTransmitInitialize
  jsr pppIcmpRetryPending
  bcc :+
  jmp fail8b
:
  lda pppTransmitActive
  cmp #$01
  pppIcmpRequireEqual fail8b
  lda pppIcmpFlags
  cmp #(PPP_ICMP_FLAG_VALID | PPP_ICMP_FLAG_ECHO_REQUEST)
  pppIcmpRequireEqual fail8b
  m16
  lda pppIcmpReceiveCount
  cmp #$0002
  pppIcmpRequireEqual fail8b_16
  lda pppIcmpTransmitCount
  cmp #$0002
  pppIcmpRequireEqual fail8b_16
  m8
  jsr pppTransmitInitialize
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12
  eor #$01
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12
  jsr pppIcmpReceive
  bcc :+
  jmp fail8c
:
  lda pppIcmpLastError
  cmp #PPP_ICMP_ERROR_INVALID_CHECKSUM
  pppIcmpRequireEqual fail8c
  lda pppIcmpInboundState
  cmp #PPP_ICMP_INBOUND_STATE_FAILED
  pppIcmpRequireEqual fail8c
  lda pppIcmpInboundLastError
  cmp #PPP_ICMP_ERROR_INVALID_CHECKSUM
  pppIcmpRequireEqual fail8c
  m16
  lda pppIcmpChecksumErrorCount
  cmp #$0001
  pppIcmpRequireEqual fail8c_16
  lda pppIcmpDropCount
  cmp #$0001
  pppIcmpRequireEqual fail8c_16
  lda pppIcmpInboundDropCount
  cmp #$0001
  pppIcmpRequireEqual fail8c_16
  lda pppIcmpInboundIdentifier
  cmp #$1234
  pppIcmpRequireEqual fail8c_16
  m8
  jsr cleanup
  lda #$00
  clc
  bra return

fail88_16:
  m8
fail88:
  lda #$88
  bra fail
fail89_16:
  m8
fail89:
  lda #$89
  bra fail
fail8a:
  lda #$8a
  bra fail
fail8b_16:
  m8
fail8b:
  lda #$8b
  bra fail
fail8c_16:
  m8
fail8c:
  lda #$8c
fail:
  pha
  jsr cleanup
  pla
  sec
return:
  ply
  plx
  plb
  rts

prepareRequest:
  .a8
  lda #PPP_IPV4_MINIMUM_HEADER_LENGTH
  sta pppIpv4HeaderLength
  lda #PPP_IPV4_PROTOCOL_ICMP
  sta pppIpv4Protocol
  lda #$c0
  sta pppIpv4SourceAddress + 0
  lda #$a8
  sta pppIpv4SourceAddress + 1
  stz pppIpv4SourceAddress + 2
  lda #$01
  sta pppIpv4SourceAddress + 3
  m16
  lda #$000d
  sta pppIpv4PayloadLength
  m8
  lda #$08
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 0
  stz pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 1
  lda #$16
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 2
  lda #$54
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 3
  lda #$12
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 4
  lda #$34
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 5
  stz pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 6
  lda #$01
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 7
  lda #$4e
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 8
  lda #$44
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 9
  lda #$4d
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 10
  lda #$32
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 11
  lda #$34
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12
  rts

cleanup:
  .a8
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppIcmpInitialize
  rts
.endproc
