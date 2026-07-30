.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import modemDriverState
.import pppSnapshotBegin, pppSnapshotEnd
.import pppReceiveEnabled, pppFrameReady, pppReleaseFrame
.import pppReceiveInitialize
.import pppTransmitInitialize
.import pppLcpState, pppPapState, pppIpcpState
.import pppLcpInitialize, pppPapInitialize, pppIpcpInitialize
.import pppLastProtocol, pppLastFrameLength, pppFrameBuffer
.import pppIpcpLocalAddress, pppIpcpFlags
.import pppIpv4LastError, pppIpv4FlagsFragmentOffset
.import pppIpv4Protocol, pppIpv4DestinationAddress, pppIpv4Flags
.import pppIpv4ReceiveCount, pppIpv4AcceptedCount, pppIpv4DropCount
.import pppIpv4PollSavedModemState
.import pppIpv4Initialize, pppIpv4ReceiveFrame
.import pppIcmpFlags, pppIcmpInitialize, pppIcmpReceive
.import pppIcmpRetryPending, pppIcmpCancelPending

.export pppIpv4Poll, pppIpv4PollRunSelfTest

; Consume protocol $0021 only after IPCP is Opened. A valid local ICMP Echo
; Request is retained until its automatic reply enters the shared transmitter.
.proc pppIpv4Poll
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
  bne :+
  jmp releaseIfOwned
:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq :+
  jmp releaseIfOwned
:
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  beq :+
  jmp releaseIfOwned
:
  lda pppPapState
  cmp #PPP_PAP_STATE_OPENED
  beq :+
  jmp releaseIfOwned
:
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_OPENED
  beq :+
  jmp releaseIfOwned
:

  lda pppFrameReady
  bne :+
  jmp done
:
  rep #$20
  .a16
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_IP
  beq :+
  jmp done
:
  sep #$20
  .a8

  lda pppIcmpFlags
  and #PPP_ICMP_FLAG_REPLY_PENDING
  beq parse
  jsr pppIcmpRetryPending
  bcc :+
  jmp done
:
  jmp release

parse:
  jsr pppIpv4ReceiveFrame
  bcs release
  jsr pppSnapshotBegin

  ; The first receive milestone accepts only the negotiated local unicast
  ; address. Broadcast and multicast policy will be added with their users.
  ldx #$0000
compareDestination:
  lda pppIpv4DestinationAddress, x
  cmp pppIpcpLocalAddress, x
  bne destinationMismatch
  inx
  cpx #$0004
  bne compareDestination
  lda pppIpv4Flags
  ora #PPP_IPV4_FLAG_DESTINATION_LOCAL
  sta pppIpv4Flags

  rep #$20
  .a16
  lda pppIpv4FlagsFragmentOffset
  and #(PPP_IPV4_FLAG_MORE_FRAGMENTS | PPP_IPV4_FRAGMENT_OFFSET_MASK)
  beq accepted
  sep #$20
  .a8
  lda pppIpv4Flags
  ora #PPP_IPV4_FLAG_FRAGMENTED
  sta pppIpv4Flags
  lda #PPP_IPV4_ERROR_FRAGMENT_UNSUPPORTED
  sta pppIpv4LastError
  pppIncrement32 pppIpv4DropCount
  bra policyDone

accepted:
  sep #$20
  .a8
  stz pppIpv4LastError
  pppIncrement32 pppIpv4AcceptedCount
  lda pppIpv4Protocol
  cmp #PPP_IPV4_PROTOCOL_ICMP
  bne policyDone
  jsr pppIcmpReceive
  bcc policyDone
  jsr pppSnapshotEnd
  bra done

policyDone:
  jsr pppSnapshotEnd
release:
  jsr pppReleaseFrame
  bra done

destinationMismatch:
  lda #PPP_IPV4_ERROR_DESTINATION_MISMATCH
  sta pppIpv4LastError
  pppIncrement32 pppIpv4DropCount
  bra policyDone

releaseIfOwned:
  lda pppFrameReady
  beq done
  rep #$20
  .a16
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_IP
  bne done
  sep #$20
  .a8
  jsr pppIcmpCancelPending
  jsr pppReleaseFrame

done:
  rep #$30
  .a16
  .i16
  ply
  plx
  plb
  pla
  rts
.endproc

.macro pppIpv4PollRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; Failure steps $85-$87 cover accepted delivery, destination filtering, and
; phase-gated release.
.proc pppIpv4PollRunSelfTest
  .a8
  .i16

  sep #$20
  rep #$10
  phb
  phx
  phy
  setDBR $7e
  lda modemDriverState
  sta pppIpv4PollSavedModemState
  jsr pppReceiveInitialize
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
  jsr pppPapInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppIcmpInitialize
  lda #MODEM_STATE_CONNECTED
  sta modemDriverState
  lda #$01
  sta pppReceiveEnabled
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  lda #PPP_PAP_STATE_OPENED
  sta pppPapState
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
  jsr @prepareFrame

  rep #$20
  .a16
  jsr pppIpv4Poll
  sep #$20
  .a8
  lda pppFrameReady
  pppIpv4PollRequireEqual @fail85
  lda pppIpv4Flags
  cmp #(PPP_IPV4_FLAG_HEADER_VALID | PPP_IPV4_FLAG_DESTINATION_LOCAL)
  pppIpv4PollRequireEqual @fail85
  rep #$20
  .a16
  lda pppIpv4ReceiveCount
  cmp #$0001
  bne @fail85_16
  lda pppIpv4AcceptedCount
  cmp #$0001
  bne @fail85_16
  sep #$20
  .a8

  ; Reuse the valid packet with a different negotiated local address.
  inc pppIpcpLocalAddress + 3
  lda #$01
  sta pppFrameReady
  rep #$20
  .a16
  jsr pppIpv4Poll
  sep #$20
  .a8
  lda pppFrameReady
  pppIpv4PollRequireEqual @fail86
  lda pppIpv4LastError
  cmp #PPP_IPV4_ERROR_DESTINATION_MISMATCH
  pppIpv4PollRequireEqual @fail86
  rep #$20
  .a16
  lda pppIpv4DropCount
  cmp #$0001
  bne @fail86_16
  sep #$20
  .a8

  ; A packet arriving below IPCP Opened is released without parsing.
  stz pppIpcpState
  lda #$01
  sta pppFrameReady
  rep #$20
  .a16
  jsr pppIpv4Poll
  sep #$20
  .a8
  lda pppFrameReady
  pppIpv4PollRequireEqual @fail87
  rep #$20
  .a16
  lda pppIpv4ReceiveCount
  cmp #$0002
  bne @fail87_16
  sep #$20
  .a8

  jsr @cleanup
  lda #$00
  clc
  bra @return

@fail85_16:
  sep #$20
  .a8
@fail85:
  lda #$85
  bra @fail
@fail86_16:
  sep #$20
  .a8
@fail86:
  lda #$86
  bra @fail
@fail87_16:
  sep #$20
  .a8
@fail87:
  lda #$87
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

@prepareFrame:
  .a8
  setDBR .bankbyte(pppIpv4PollSelfTestFrameHeader)
  ldx #$0000
@copy:
  lda pppIpv4PollSelfTestFrameHeader, x
  pha
  setDBR $7e
  pla
  sta pppFrameBuffer, x
  setDBR .bankbyte(pppIpv4PollSelfTestFrameHeader)
  inx
  cpx #(pppIpv4PollSelfTestFrameHeaderEnd - pppIpv4PollSelfTestFrameHeader)
  bne @copy
  setDBR $7e
  lda #$00
@payload:
  sta pppFrameBuffer, x
  inx
  cpx #$0077
  bne @payload
  rep #$20
  .a16
  lda #PPP_PROTOCOL_IP
  sta pppLastProtocol
  lda #$0077
  sta pppLastFrameLength
  sep #$20
  .a8
  lda #$01
  sta pppFrameReady
  rts

@cleanup:
  .a8
  lda pppIpv4PollSavedModemState
  sta modemDriverState
  jsr pppReceiveInitialize
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
  jsr pppPapInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppIcmpInitialize
  rts
.endproc

pppIpv4PollSelfTestFrameHeader:
  .byte $ff, $03, $00, $21
  .byte $45, $00, $00, $73, $00, $00, $40, $00
  .byte $40, $11, $b8, $61, $c0, $a8, $00, $01
  .byte $c0, $a8, $00, $c7
pppIpv4PollSelfTestFrameHeaderEnd:
