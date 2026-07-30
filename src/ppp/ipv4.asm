.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppSnapshotBegin, pppSnapshotEnd
.import pppLastProtocol, pppLastFrameLength, pppFrameBuffer
.import pppTransmitActive, pppTransmitBuffer, pppTransmitBegin
.import pppTransmitInitialize
.import pppIpcpState, pppIpcpFlags, pppIpcpLocalAddress
.import pppIpcpInitialize
.import pppIpv4LastError, pppIpv4HeaderLength, pppIpv4Protocol, pppIpv4Ttl
.import pppIpv4TotalLength, pppIpv4PayloadLength, pppIpv4Identification
.import pppIpv4FlagsFragmentOffset, pppIpv4HeaderChecksum
.import pppIpv4SourceAddress, pppIpv4DestinationAddress
.import pppIpv4ReceiveCount, pppIpv4AcceptedCount
.import pppIpv4ChecksumErrorCount, pppIpv4DropCount, pppIpv4TransmitCount
.import pppIpv4NextIdentification, pppIpv4Flags
.import pppIpv4ChecksumAccumulator, pppIpv4AvailableLength
.import pppIpv4TransmitDestination, pppIpv4TransmitProtocol
.import pppIpv4TransmitPayloadLength

.export pppIpv4Initialize, pppIpv4ReceiveFrame, pppIpv4BeginTransmit
.export pppIpv4RunSelfTest

.macro pppIpv4ReceiveError error
  lda #error
  sta pppIpv4LastError
  pppIncrement32 pppIpv4DropCount
  jsr pppSnapshotEnd
  ply
  plx
  plb
  sec
  rts
.endmacro

.macro pppIpv4RequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; The explicit 8-to-16 transition is intentional. The FXPAK PRO hardware
; self-test exposed a stale accumulator-width path at these parser boundaries
; when only REP was repeated. Keep both instructions at each A16 parse block.
.macro pppIpv4EnterA16
  sep #$20
  .a8
  rep #$20
  .a16
.endmacro

.proc pppIpv4Initialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppIpv4LastError
  stz pppIpv4HeaderLength
  stz pppIpv4Protocol
  stz pppIpv4Ttl
  stz pppIpv4Flags
  stz pppIpv4SourceAddress + 0
  stz pppIpv4SourceAddress + 1
  stz pppIpv4SourceAddress + 2
  stz pppIpv4SourceAddress + 3
  stz pppIpv4DestinationAddress + 0
  stz pppIpv4DestinationAddress + 1
  stz pppIpv4DestinationAddress + 2
  stz pppIpv4DestinationAddress + 3
  stz pppIpv4TransmitDestination + 0
  stz pppIpv4TransmitDestination + 1
  stz pppIpv4TransmitDestination + 2
  stz pppIpv4TransmitDestination + 3
  stz pppIpv4TransmitProtocol
  rep #$20
  .a16
  stz pppIpv4TotalLength
  stz pppIpv4PayloadLength
  stz pppIpv4Identification
  stz pppIpv4FlagsFragmentOffset
  stz pppIpv4HeaderChecksum
  stz pppIpv4ReceiveCount
  stz pppIpv4ReceiveCount + 2
  stz pppIpv4AcceptedCount
  stz pppIpv4AcceptedCount + 2
  stz pppIpv4ChecksumErrorCount
  stz pppIpv4ChecksumErrorCount + 2
  stz pppIpv4DropCount
  stz pppIpv4DropCount + 2
  stz pppIpv4TransmitCount
  stz pppIpv4TransmitCount + 2
  stz pppIpv4NextIdentification
  stz pppIpv4ChecksumAccumulator
  stz pppIpv4AvailableLength
  stz pppIpv4TransmitPayloadLength
  sep #$20
  .a8
  plb
  rts
.endproc

; Parse one FCS-verified PPP IPv4 frame. Variable IHL is accepted, Total
; Length delimits padding, and the complete header checksum must sum to $ffff.
;
; Carry clear means the header is structurally valid. Fragment and destination
; policy is applied by pppIpv4Poll.
.proc pppIpv4ReceiveFrame
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppSnapshotBegin
  pppIncrement32 pppIpv4ReceiveCount
  stz pppIpv4LastError
  stz pppIpv4HeaderLength
  stz pppIpv4Protocol
  stz pppIpv4Ttl
  stz pppIpv4Flags
  rep #$20
  .a16
  stz pppIpv4TotalLength
  stz pppIpv4PayloadLength
  stz pppIpv4Identification
  stz pppIpv4FlagsFragmentOffset
  stz pppIpv4HeaderChecksum
  pppIpv4EnterA16

  lda pppLastProtocol
  cmp #PPP_PROTOCOL_IP
  beq minimumFrame
  sep #$20
  .a8
  pppIpv4ReceiveError PPP_IPV4_ERROR_WRONG_PROTOCOL

minimumFrame:
  pppIpv4EnterA16
  lda pppLastFrameLength
  cmp #PPP_IPV4_MINIMUM_FRAME_LENGTH
  bcs available
  sep #$20
  .a8
  pppIpv4ReceiveError PPP_IPV4_ERROR_TRUNCATED_MINIMUM_HEADER

available:
  ; Do not rely on A surviving the validation branch. Reloading also makes the
  ; routine robust when instrumentation is inserted between compare and use.
  pppIpv4EnterA16
  lda pppLastFrameLength
  sec
  sbc #PPP_IPV4_FRAME_OFFSET
  sta pppIpv4AvailableLength
  sep #$20
  .a8

  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET
  and #$f0
  cmp #(PPP_IPV4_VERSION << 4)
  beq ihl
  pppIpv4ReceiveError PPP_IPV4_ERROR_UNSUPPORTED_VERSION

ihl:
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET
  and #$0f
  cmp #PPP_IPV4_MINIMUM_IHL_WORDS
  bcs :+
  pppIpv4ReceiveError PPP_IPV4_ERROR_INVALID_HEADER_LENGTH
:
  asl
  asl
  sta pppIpv4HeaderLength
  sta pppIpv4PayloadLength
  stz pppIpv4PayloadLength + 1

  rep #$20
  .a16
  and #$00ff
  cmp pppIpv4AvailableLength
  bcc readTotal
  beq readTotal
  sep #$20
  .a8
  pppIpv4ReceiveError PPP_IPV4_ERROR_TRUNCATED_HEADER

readTotal:
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 2
  xba
  sta pppIpv4TotalLength
  cmp pppIpv4PayloadLength
  bcs totalAvailable
  sep #$20
  .a8
  pppIpv4ReceiveError PPP_IPV4_ERROR_INVALID_TOTAL_LENGTH

totalAvailable:
  cmp pppIpv4AvailableLength
  bcc readFields
  beq readFields
  sep #$20
  .a8
  pppIpv4ReceiveError PPP_IPV4_ERROR_TRUNCATED_PACKET

readFields:
  pppIpv4EnterA16
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 4
  xba
  sta pppIpv4Identification
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 6
  xba
  sta pppIpv4FlagsFragmentOffset
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 10
  xba
  sta pppIpv4HeaderChecksum
  lda pppIpv4TotalLength
  sec
  sbc pppIpv4PayloadLength
  sta pppIpv4PayloadLength
  sep #$20
  .a8

  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 8
  sta pppIpv4Ttl
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 9
  sta pppIpv4Protocol
  ldx #$0000
copyAddresses:
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 12, x
  sta pppIpv4SourceAddress, x
  lda pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 16, x
  sta pppIpv4DestinationAddress, x
  inx
  cpx #$0004
  bne copyAddresses

  ldx #PPP_IPV4_FRAME_OFFSET
  jsr checksumReceiveHeader
  rep #$20
  .a16
  cmp #$ffff
  beq valid
  sep #$20
  .a8
  pppIncrement32 pppIpv4ChecksumErrorCount
  pppIpv4ReceiveError PPP_IPV4_ERROR_INVALID_HEADER_CHECKSUM

valid:
  sep #$20
  .a8
  lda #PPP_IPV4_FLAG_HEADER_VALID
  sta pppIpv4Flags
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts

; X is the IPv4 header offset in pppFrameBuffer. Returns A16 folded sum.
checksumReceiveHeader:
  .a8
  .i16
  rep #$20
  .a16
  stz pppIpv4ChecksumAccumulator
  sep #$20
  .a8
  lda pppIpv4HeaderLength
  lsr
  rep #$20
  .a16
  and #$00ff
  tay
checksumReceiveWord:
  lda pppFrameBuffer, x
  xba
  clc
  adc pppIpv4ChecksumAccumulator
  sta pppIpv4ChecksumAccumulator
  bcc :+
  inc pppIpv4ChecksumAccumulator
:
  inx
  inx
  dey
  bne checksumReceiveWord
  lda pppIpv4ChecksumAccumulator
  rts
.endproc

; Build a 20-byte IPv4 header around a payload already staged at
; pppTransmitBuffer + 24, then submit it to the shared PPP encoder.
;
; Input A8=IPv4 Protocol, X16=payload length. Destination is provided in
; pppIpv4TransmitDestination. Carry set means the packet was not accepted.
.proc pppIpv4BeginTransmit
  .a8
  .i16

  phb
  phy
  setDBR $7e
  sta pppIpv4TransmitProtocol

  lda pppIpcpState
  cmp #PPP_IPCP_STATE_OPENED
  beq :+
  jmp linkClosed
:
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_LOCAL_VALID
  bne :+
  jmp linkClosed
:
  lda pppTransmitActive
  beq :+
  jmp busy
:
  cpx #(PPP_IPV4_MAXIMUM_PAYLOAD_LENGTH + 1)
  bcc :+
  jmp tooLong
:

  stx pppIpv4TransmitPayloadLength
  rep #$20
  .a16
  txa
  clc
  adc #PPP_IPV4_MINIMUM_HEADER_LENGTH
  sta pppIpv4AvailableLength

  sep #$20
  .a8
  lda #$ff
  sta pppTransmitBuffer + 0
  lda #$03
  sta pppTransmitBuffer + 1
  stz pppTransmitBuffer + 2
  lda #$21
  sta pppTransmitBuffer + 3
  lda #((PPP_IPV4_VERSION << 4) | PPP_IPV4_MINIMUM_IHL_WORDS)
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 0
  stz pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 1

  rep #$20
  .a16
  lda pppIpv4AvailableLength
  xba
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 2
  lda pppIpv4NextIdentification
  xba
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 4
  lda #PPP_IPV4_FLAG_DONT_FRAGMENT
  xba
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 6
  sep #$20
  .a8
  lda #PPP_IPV4_DEFAULT_TTL
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 8
  lda pppIpv4TransmitProtocol
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 9
  stz pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 10
  stz pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 11

  ldx #$0000
copyTransmitAddresses:
  lda pppIpcpLocalAddress, x
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 12, x
  lda pppIpv4TransmitDestination, x
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 16, x
  inx
  cpx #$0004
  bne copyTransmitAddresses

  jsr checksumTransmitHeader
  rep #$20
  .a16
  eor #$ffff
  xba
  sta pppTransmitBuffer + PPP_IPV4_FRAME_OFFSET + 10

  lda pppIpv4AvailableLength
  clc
  adc #PPP_UNCOMPRESSED_HEADER_LENGTH
  jsr pppTransmitBegin
  bcs busy16

  sep #$20
  .a8
  jsr pppSnapshotBegin
  rep #$20
  .a16
  inc pppIpv4NextIdentification
  sep #$20
  .a8
  pppIncrement32 pppIpv4TransmitCount
  stz pppIpv4LastError
  jsr pppSnapshotEnd
  ply
  plb
  clc
  rts

busy16:
  sep #$20
  .a8
busy:
  lda #PPP_IPV4_ERROR_TRANSMIT_BUSY
  bra transmitError
linkClosed:
  lda #PPP_IPV4_ERROR_LINK_NOT_OPEN
  bra transmitError
tooLong:
  lda #PPP_IPV4_ERROR_PAYLOAD_TOO_LONG
transmitError:
  pha
  jsr pppSnapshotBegin
  pla
  sta pppIpv4LastError
  jsr pppSnapshotEnd
  ply
  plb
  sec
  rts

checksumTransmitHeader:
  .a8
  .i16
  rep #$20
  .a16
  stz pppIpv4ChecksumAccumulator
  ldx #PPP_IPV4_FRAME_OFFSET
  ldy #(PPP_IPV4_MINIMUM_HEADER_LENGTH / 2)
checksumTransmitWord:
  lda pppTransmitBuffer, x
  xba
  clc
  adc pppIpv4ChecksumAccumulator
  sta pppIpv4ChecksumAccumulator
  bcc :+
  inc pppIpv4ChecksumAccumulator
:
  inx
  inx
  dey
  bne checksumTransmitWord
  lda pppIpv4ChecksumAccumulator
  rts
.endproc

; Fixed-vector parser and encoder test. Failure steps $80-$84 are reserved
; for the IPv4 core.
.proc pppIpv4RunSelfTest
  .a8
  .i16

  sep #$20
  rep #$10
  phb
  phx
  phy
  setDBR $7e
  jsr pppIpv4Initialize
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize

  setDBR .bankbyte(pppIpv4SelfTestFrameHeader)
  ldx #$0000
@copyHeader:
  lda pppIpv4SelfTestFrameHeader, x
  pha
  setDBR $7e
  pla
  sta pppFrameBuffer, x
  setDBR .bankbyte(pppIpv4SelfTestFrameHeader)
  inx
  cpx #(pppIpv4SelfTestFrameHeaderEnd - pppIpv4SelfTestFrameHeader)
  bne @copyHeader
  setDBR $7e
  lda #$00
@clearPayload:
  sta pppFrameBuffer, x
  inx
  cpx #$0077
  bne @clearPayload
  rep #$20
  .a16
  lda #PPP_PROTOCOL_IP
  sta pppLastProtocol
  lda #$0077
  sta pppLastFrameLength
  sep #$20
  .a8

  jsr pppIpv4ReceiveFrame
  bcc :+
  jmp @fail80
:
  lda pppIpv4HeaderLength
  cmp #PPP_IPV4_MINIMUM_HEADER_LENGTH
  pppIpv4RequireEqual @fail80
  lda pppIpv4Protocol
  cmp #PPP_IPV4_PROTOCOL_UDP
  pppIpv4RequireEqual @fail80
  lda pppIpv4Ttl
  cmp #PPP_IPV4_DEFAULT_TTL
  pppIpv4RequireEqual @fail80
  lda pppIpv4SourceAddress + 3
  cmp #$01
  pppIpv4RequireEqual @fail80
  lda pppIpv4DestinationAddress + 3
  cmp #$c7
  pppIpv4RequireEqual @fail80
  rep #$20
  .a16
  lda pppIpv4TotalLength
  cmp #$0073
  pppIpv4RequireEqual @fail80_16
  lda pppIpv4PayloadLength
  cmp #$005f
  pppIpv4RequireEqual @fail80_16
  lda pppIpv4HeaderChecksum
  cmp #$b861
  pppIpv4RequireEqual @fail80_16
  sep #$20
  .a8

  ; Corrupt TTL without replacing the checksum.
  inc pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 8
  jsr pppIpv4ReceiveFrame
  bcs :+
  jmp @fail81
:
  lda pppIpv4LastError
  cmp #PPP_IPV4_ERROR_INVALID_HEADER_CHECKSUM
  pppIpv4RequireEqual @fail81
  rep #$20
  .a16
  lda pppIpv4ChecksumErrorCount
  cmp #$0001
  pppIpv4RequireEqual @fail81_16
  lda pppIpv4DropCount
  cmp #$0001
  pppIpv4RequireEqual @fail81_16
  sep #$20
  .a8
  dec pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + 8

  ; Rebuild the same known header through the shared transmit entry.
  jsr pppTransmitInitialize
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
  ldx #$0018
  lda #$00
@clearTransmitPayload:
  sta pppTransmitBuffer, x
  inx
  cpx #$0077
  bne @clearTransmitPayload
  lda #PPP_IPV4_PROTOCOL_UDP
  ldx #$005f
  jsr pppIpv4BeginTransmit
  bcc :+
  jmp @fail82
:

  setDBR .bankbyte(pppIpv4SelfTestFrameHeader)
  ldx #$0000
@compareTransmitHeader:
  lda pppIpv4SelfTestFrameHeader, x
  pha
  setDBR $7e
  pla
  cmp pppTransmitBuffer, x
  bne @fail83
  setDBR .bankbyte(pppIpv4SelfTestFrameHeader)
  inx
  cpx #(pppIpv4SelfTestFrameHeaderEnd - pppIpv4SelfTestFrameHeader)
  bne @compareTransmitHeader
  setDBR $7e
  lda pppTransmitActive
  bne :+
  jmp @fail84
:
  rep #$20
  .a16
  lda pppIpv4NextIdentification
  cmp #$0001
  bne @fail84_16
  lda pppIpv4TransmitCount
  cmp #$0001
  bne @fail84_16
  sep #$20
  .a8

  jsr @cleanup
  lda #$00
  clc
  bra @return

@fail80_16:
  sep #$20
  .a8
@fail80:
  lda #$80
  bra @fail
@fail81_16:
  sep #$20
  .a8
@fail81:
  lda #$81
  bra @fail
@fail82:
  lda #$82
  bra @fail
@fail83:
  lda #$83
  bra @fail
@fail84_16:
  sep #$20
  .a8
@fail84:
  lda #$84
@fail:
  pha
  setDBR $7e
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
  jsr pppIpv4Initialize
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  rts
.endproc

pppIpv4SelfTestFrameHeader:
  .byte $ff, $03, $00, $21
  .byte $45, $00, $00, $73, $00, $00, $40, $00
  .byte $40, $11, $b8, $61, $c0, $a8, $00, $01
  .byte $c0, $a8, $00, $c7
pppIpv4SelfTestFrameHeaderEnd:
