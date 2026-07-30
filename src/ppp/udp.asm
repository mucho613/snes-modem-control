.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppSnapshotBegin, pppSnapshotEnd
.import pppFrameBuffer, pppTransmitBuffer
.import pppTransmitInitialize
.import pppIpcpState, pppIpcpFlags, pppIpcpLocalAddress
.import pppIpcpInitialize
.import pppIpv4HeaderLength, pppIpv4PayloadLength
.import pppIpv4SourceAddress, pppIpv4DestinationAddress
.import pppIpv4TransmitDestination, pppIpv4BeginTransmit
.import pppIpv4TransmitCount, pppIpv4Initialize
.import pppUdpLastError, pppUdpFlags
.import pppUdpSourcePort, pppUdpDestinationPort
.import pppUdpLength, pppUdpPayloadLength, pppUdpChecksum
.import pppUdpReceiveCount, pppUdpChecksumErrorCount
.import pppUdpDropCount, pppUdpTransmitCount
.import pppUdpPacketOffset, pppUdpChecksumAccumulator
.import pppUdpTransmitSourcePort, pppUdpTransmitDestinationPort
.import pppNtpReceive

.export pppUdpInitialize, pppUdpReceive, pppUdpBeginTransmit
.export pppUdpRunSelfTest

.macro pppUdpReceiveError error
  lda #error
  sta pppUdpLastError
  pppIncrement32 pppUdpDropCount
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts
.endmacro

.macro pppUdpEnterA16
  sep #$20
  .a8
  rep #$20
  .a16
.endmacro

.proc pppUdpInitialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppUdpLastError
  stz pppUdpFlags
  rep #$20
  .a16
  stz pppUdpSourcePort
  stz pppUdpDestinationPort
  stz pppUdpLength
  stz pppUdpPayloadLength
  stz pppUdpChecksum
  stz pppUdpReceiveCount
  stz pppUdpReceiveCount + 2
  stz pppUdpChecksumErrorCount
  stz pppUdpChecksumErrorCount + 2
  stz pppUdpDropCount
  stz pppUdpDropCount + 2
  stz pppUdpTransmitCount
  stz pppUdpTransmitCount + 2
  stz pppUdpPacketOffset
  stz pppUdpChecksumAccumulator
  stz pppUdpTransmitSourcePort
  stz pppUdpTransmitDestinationPort
  sep #$20
  .a8
  plb
  rts
.endproc

; Parse one UDP datagram from the current, already validated local and
; unfragmented IPv4 packet. A zero checksum is accepted as IPv4 UDP checksum
; omission. Carry is always clear because no application owns the frame yet.
.proc pppUdpReceive
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppSnapshotBegin
  pppIncrement32 pppUdpReceiveCount
  stz pppUdpLastError
  stz pppUdpFlags
  rep #$20
  .a16
  stz pppUdpSourcePort
  stz pppUdpDestinationPort
  stz pppUdpLength
  stz pppUdpPayloadLength
  stz pppUdpChecksum

  lda pppIpv4PayloadLength
  cmp #PPP_UDP_HEADER_LENGTH
  bcs packetOffset
  sep #$20
  .a8
  pppUdpReceiveError PPP_UDP_ERROR_TRUNCATED_HEADER

packetOffset:
  sep #$20
  .a8
  lda pppIpv4HeaderLength
  rep #$20
  .a16
  and #$00ff
  clc
  adc #PPP_IPV4_FRAME_OFFSET
  sta pppUdpPacketOffset
  tax

  lda pppFrameBuffer + 0, x
  xba
  sta pppUdpSourcePort
  lda pppFrameBuffer + 2, x
  xba
  sta pppUdpDestinationPort
  lda pppFrameBuffer + 4, x
  xba
  sta pppUdpLength
  cmp #PPP_UDP_HEADER_LENGTH
  bcs lengthAvailable
  sep #$20
  .a8
  pppUdpReceiveError PPP_UDP_ERROR_INVALID_LENGTH

lengthAvailable:
  pppUdpEnterA16
  cmp pppIpv4PayloadLength
  bcc readChecksum
  beq readChecksum
  sep #$20
  .a8
  pppUdpReceiveError PPP_UDP_ERROR_TRUNCATED_DATAGRAM

readChecksum:
  pppUdpEnterA16
  lda pppFrameBuffer + 6, x
  xba
  sta pppUdpChecksum
  lda pppUdpLength
  sec
  sbc #PPP_UDP_HEADER_LENGTH
  sta pppUdpPayloadLength
  lda pppUdpChecksum
  beq valid

  jsr checksumReceiveDatagram
  rep #$20
  .a16
  cmp #$ffff
  beq checksumValid
  sep #$20
  .a8
  pppIncrement32 pppUdpChecksumErrorCount
  pppUdpReceiveError PPP_UDP_ERROR_INVALID_CHECKSUM

checksumValid:
  sep #$20
  .a8
  lda #PPP_UDP_FLAG_CHECKSUM_PRESENT
  sta pppUdpFlags

valid:
  sep #$20
  .a8
  lda pppUdpFlags
  ora #PPP_UDP_FLAG_VALID
  sta pppUdpFlags
  stz pppUdpLastError
  rep #$20
  .a16
  lda pppUdpDestinationPort
  cmp #PPP_NTP_CLIENT_PORT
  bne applicationDone
  sep #$20
  .a8
  jsr pppNtpReceive
  bra applicationDone8
applicationDone:
  sep #$20
  .a8
applicationDone8:
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

checksumReceiveDatagram:
  .a16
  .i16
  stz pppUdpChecksumAccumulator

  lda pppIpv4SourceAddress + 0
  xba
  jsr addChecksumWord
  lda pppIpv4SourceAddress + 2
  xba
  jsr addChecksumWord
  lda pppIpv4DestinationAddress + 0
  xba
  jsr addChecksumWord
  lda pppIpv4DestinationAddress + 2
  xba
  jsr addChecksumWord
  lda #PPP_IPV4_PROTOCOL_UDP
  jsr addChecksumWord
  lda pppUdpLength
  jsr addChecksumWord

  ldx pppUdpPacketOffset
  lda pppUdpLength
  lsr
  tay
@word:
  lda pppFrameBuffer, x
  xba
  jsr addChecksumWord
  inx
  inx
  dey
  bne @word

  lda pppUdpLength
  and #$0001
  beq @done
  sep #$20
  .a8
  lda pppFrameBuffer, x
  rep #$20
  .a16
  and #$00ff
  xba
  jsr addChecksumWord
@done:
  lda pppUdpChecksumAccumulator
  rts

addChecksumWord:
  .a16
  clc
  adc pppUdpChecksumAccumulator
  sta pppUdpChecksumAccumulator
  bcc :+
  inc pppUdpChecksumAccumulator
:
  rts
.endproc

; Build a UDP header around a payload already staged at
; pppTransmitBuffer + 32 and submit the surrounding IPv4 packet.
;
; Input X16=payload length. Source and destination ports are provided in
; pppUdpTransmitSourcePort and pppUdpTransmitDestinationPort; destination
; address is provided in pppIpv4TransmitDestination. Carry set means rejected.
.proc pppUdpBeginTransmit
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppSnapshotBegin
  cpx #(PPP_UDP_MAXIMUM_PAYLOAD_LENGTH + 1)
  bcc lengthValid
  lda #PPP_UDP_ERROR_PAYLOAD_TOO_LONG
  bra transmitError

lengthValid:
  rep #$20
  .a16
  txa
  clc
  adc #PPP_UDP_HEADER_LENGTH
  sta pppUdpLength
  stx pppUdpPayloadLength
  lda pppUdpTransmitSourcePort
  xba
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 0
  lda pppUdpTransmitDestinationPort
  xba
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 2
  lda pppUdpLength
  xba
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 4
  stz pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 6

  jsr checksumTransmitDatagram
  rep #$20
  .a16
  eor #$ffff
  bne :+
  lda #$ffff
:
  sta pppUdpChecksum
  xba
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 6

  ldx pppUdpLength
  sep #$20
  .a8
  lda #PPP_IPV4_PROTOCOL_UDP
  jsr pppIpv4BeginTransmit
  bcc transmitAccepted
  lda #PPP_UDP_ERROR_TRANSMIT_FAILED
  bra transmitError

transmitAccepted:
  pppIncrement32 pppUdpTransmitCount
  stz pppUdpLastError
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

transmitError:
  sta pppUdpLastError
  pppIncrement32 pppUdpDropCount
  jsr pppSnapshotEnd
  ply
  plx
  plb
  sec
  rts

checksumTransmitDatagram:
  .a16
  .i16
  stz pppUdpChecksumAccumulator

  lda pppIpcpLocalAddress + 0
  xba
  jsr addChecksumWord
  lda pppIpcpLocalAddress + 2
  xba
  jsr addChecksumWord
  lda pppIpv4TransmitDestination + 0
  xba
  jsr addChecksumWord
  lda pppIpv4TransmitDestination + 2
  xba
  jsr addChecksumWord
  lda #PPP_IPV4_PROTOCOL_UDP
  jsr addChecksumWord
  lda pppUdpLength
  jsr addChecksumWord

  ldx #(PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH)
  lda pppUdpLength
  lsr
  tay
@word:
  lda pppTransmitBuffer, x
  xba
  jsr addChecksumWord
  inx
  inx
  dey
  bne @word

  lda pppUdpLength
  and #$0001
  beq @done
  sep #$20
  .a8
  lda pppTransmitBuffer, x
  rep #$20
  .a16
  and #$00ff
  xba
  jsr addChecksumWord
@done:
  lda pppUdpChecksumAccumulator
  rts

addChecksumWord:
  .a16
  clc
  adc pppUdpChecksumAccumulator
  sta pppUdpChecksumAccumulator
  bcc :+
  inc pppUdpChecksumAccumulator
:
  rts
.endproc

.macro pppUdpRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; Fixed odd-length datagram vectors, checksum omission, malformed input, and
; transmit construction. Failure steps $8d-$98 are reserved for UDP.
.proc pppUdpRunSelfTest
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
  jsr pppUdpInitialize
  jsr prepareDatagram

  jsr pppUdpReceive
  lda pppUdpLastError
  pppUdpRequireEqual fail8d
initialValid:
  lda pppUdpFlags
  cmp #(PPP_UDP_FLAG_VALID | PPP_UDP_FLAG_CHECKSUM_PRESENT)
  pppUdpRequireEqual fail92
  rep #$20
  .a16
  lda pppUdpSourcePort
  cmp #$c000
  pppUdpRequireEqual fail93_16
  lda pppUdpDestinationPort
  cmp #$007b
  pppUdpRequireEqual fail94_16
  lda pppUdpLength
  cmp #$000d
  pppUdpRequireEqual fail95_16
  lda pppUdpPayloadLength
  cmp #$0005
  pppUdpRequireEqual fail96_16
  lda pppUdpChecksum
  cmp #$edc8
  pppUdpRequireEqual fail97_16
  lda pppUdpReceiveCount
  cmp #$0001
  pppUdpRequireEqual fail98_16

  ; A zero IPv4 UDP checksum is explicitly valid and skips verification.
  stz pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 6
  sep #$20
  .a8
  jsr pppUdpReceive
  lda pppUdpFlags
  cmp #PPP_UDP_FLAG_VALID
  pppUdpRequireEqual fail8e
  rep #$20
  .a16
  lda pppUdpReceiveCount
  cmp #$0002
  pppUdpRequireEqual fail8e_16

  ; Restore the checksum and corrupt the odd final payload byte.
  lda #$c8ed
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 6
  sep #$20
  .a8
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12
  eor #$01
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12
  jsr pppUdpReceive
  lda pppUdpLastError
  cmp #PPP_UDP_ERROR_INVALID_CHECKSUM
  pppUdpRequireEqual fail8f
  rep #$20
  .a16
  lda pppUdpChecksumErrorCount
  cmp #$0001
  pppUdpRequireEqual fail8f_16
  lda pppUdpDropCount
  cmp #$0001
  pppUdpRequireEqual fail8f_16

  ; A length below the fixed header is structurally invalid.
  sep #$20
  .a8
  lda #$34
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 12
  stz pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 4
  lda #$07
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 5
  jsr pppUdpReceive
  lda pppUdpLastError
  cmp #PPP_UDP_ERROR_INVALID_LENGTH
  pppUdpRequireEqual fail90

  ; Rebuild the same datagram through the shared IPv4 transmitter.
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  lda #PPP_IPCP_STATE_OPENED
  sta pppIpcpState
  lda #PPP_IPCP_FLAG_LOCAL_VALID
  sta pppIpcpFlags
  lda #$c0
  sta pppIpcpLocalAddress + 0
  lda #$a8
  sta pppIpcpLocalAddress + 1
  stz pppIpcpLocalAddress + 2
  lda #$01
  sta pppIpcpLocalAddress + 3
  lda #$c0
  sta pppIpv4TransmitDestination + 0
  lda #$a8
  sta pppIpv4TransmitDestination + 1
  stz pppIpv4TransmitDestination + 2
  lda #$c7
  sta pppIpv4TransmitDestination + 3
  rep #$20
  .a16
  lda #$c000
  sta pppUdpTransmitSourcePort
  lda #$007b
  sta pppUdpTransmitDestinationPort
  sep #$20
  .a8
  lda #$4e
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 0
  lda #$44
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 1
  lda #$4d
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 2
  lda #$32
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 3
  lda #$34
  sta pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 4
  ldx #$0005
  jsr pppUdpBeginTransmit
  bcc :+
  jmp fail91
:
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 6
  cmp #$ed
  pppUdpRequireEqual fail91
  lda pppTransmitBuffer + PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH + 7
  cmp #$c8
  pppUdpRequireEqual fail91
  rep #$20
  .a16
  lda pppUdpTransmitCount
  cmp #$0001
  pppUdpRequireEqual fail91_16
  lda pppIpv4TransmitCount
  cmp #$0001
  pppUdpRequireEqual fail91_16

  sep #$20
  .a8
  jsr cleanup
  lda #$00
  clc
  bra return

fail8d_16:
  sep #$20
  .a8
fail8d:
  lda #$8d
  bra fail
fail8e_16:
  sep #$20
  .a8
fail8e:
  lda #$8e
  bra fail
fail8f_16:
  sep #$20
  .a8
fail8f:
  lda #$8f
  bra fail
fail90:
  lda #$90
  bra fail
fail91_16:
  sep #$20
  .a8
fail91:
  lda #$91
  bra fail
fail92:
  lda #$92
  bra fail
fail93_16:
  sep #$20
  .a8
  lda #$93
  bra fail
fail94_16:
  sep #$20
  .a8
  lda #$94
  bra fail
fail95_16:
  sep #$20
  .a8
  lda #$95
  bra fail
fail96_16:
  sep #$20
  .a8
  lda #$96
  bra fail
fail97_16:
  sep #$20
  .a8
  lda #$97
  bra fail
fail98_16:
  sep #$20
  .a8
  lda #$98
  bra fail
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

prepareDatagram:
  .a8
  lda #PPP_IPV4_MINIMUM_HEADER_LENGTH
  sta pppIpv4HeaderLength
  lda #$c0
  sta pppIpv4SourceAddress + 0
  sta pppIpv4DestinationAddress + 0
  lda #$a8
  sta pppIpv4SourceAddress + 1
  sta pppIpv4DestinationAddress + 1
  stz pppIpv4SourceAddress + 2
  stz pppIpv4DestinationAddress + 2
  lda #$01
  sta pppIpv4SourceAddress + 3
  lda #$c7
  sta pppIpv4DestinationAddress + 3
  rep #$20
  .a16
  lda #$000d
  sta pppIpv4PayloadLength
  sep #$20
  .a8
  lda #$c0
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 0
  stz pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 1
  stz pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 2
  lda #$7b
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 3
  stz pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 4
  lda #$0d
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 5
  lda #$ed
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + 6
  lda #$c8
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
  jsr pppUdpInitialize
  rts
.endproc
