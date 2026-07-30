.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import frameCounter
.import pppSnapshotBegin, pppSnapshotEnd
.import pppFrameBuffer, pppTransmitActive, pppTransmitBuffer, pppTransmitInitialize
.import pppIpcpState, pppIpcpFlags, pppIpcpPeerAddress
.import pppIpcpInitialize
.import pppIpv4SourceAddress, pppIpv4TransmitDestination
.import pppIpv4Initialize
.import pppUdpFlags, pppUdpSourcePort, pppUdpDestinationPort
.import pppUdpPayloadLength, pppUdpPacketOffset
.import pppUdpTransmitSourcePort, pppUdpTransmitDestinationPort
.import pppUdpBeginTransmit, pppUdpInitialize
.import pppNtpState, pppNtpLastError, pppNtpFlags, pppNtpVersion
.import pppNtpLeapIndicator, pppNtpStratum, pppNtpPollExponent, pppNtpPrecision
.import pppNtpReferenceId, pppNtpCookieSeconds, pppNtpCookieFraction
.import pppNtpServerReceiveSeconds, pppNtpServerReceiveFraction
.import pppNtpServerTransmitSeconds, pppNtpServerTransmitFraction
.import pppNtpUnixSeconds, pppNtpDeadline
.import pppNtpRequestCount, pppNtpResponseCount
.import pppNtpDropCount, pppNtpTimeoutCount
.import pppNtpPacketOffset, pppNtpTestSavedFrameCounter
.import pppNtpTestSavedClockValid, pppNtpTestSavedClockSeconds
.import pppNtpTestSavedClockSubsecond
.import clockInitialize, clockSetUnixTime, clockAdvanceFrames
.import clockValid, clockUnixSeconds, clockSubsecond
.import clockYear, clockMonth, clockDay
.import clockHour, clockMinute, clockSecond

.export pppNtpInitialize, pppNtpRequest, pppNtpPoll, pppNtpReceive
.export pppNtpRunSelfTest

.macro pppNtpFail error
  lda #PPP_NTP_STATE_FAILED
  sta pppNtpState
  lda #error
  sta pppNtpLastError
  lda pppNtpFlags
  and #PPP_NTP_FLAG_COOKIE_VALID
  sta pppNtpFlags
  pppIncrement32 pppNtpDropCount
.endmacro

.proc pppNtpInitialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppNtpState
  stz pppNtpLastError
  stz pppNtpFlags
  stz pppNtpVersion
  stz pppNtpLeapIndicator
  stz pppNtpStratum
  stz pppNtpPollExponent
  stz pppNtpPrecision
  m16
  stz pppNtpReferenceId
  stz pppNtpReferenceId + 2
  stz pppNtpCookieSeconds
  stz pppNtpCookieSeconds + 2
  stz pppNtpCookieFraction
  stz pppNtpCookieFraction + 2
  stz pppNtpServerReceiveSeconds
  stz pppNtpServerReceiveSeconds + 2
  stz pppNtpServerReceiveFraction
  stz pppNtpServerReceiveFraction + 2
  stz pppNtpServerTransmitSeconds
  stz pppNtpServerTransmitSeconds + 2
  stz pppNtpServerTransmitFraction
  stz pppNtpServerTransmitFraction + 2
  stz pppNtpUnixSeconds
  stz pppNtpUnixSeconds + 2
  stz pppNtpDeadline
  stz pppNtpRequestCount
  stz pppNtpRequestCount + 2
  stz pppNtpResponseCount
  stz pppNtpResponseCount + 2
  stz pppNtpDropCount
  stz pppNtpDropCount + 2
  stz pppNtpTimeoutCount
  stz pppNtpTimeoutCount + 2
  stz pppNtpPacketOffset
  m8
  plb
  rts
.endproc

; Queue one explicit request. The main-loop poll waits for the shared PPP
; transmitter and sends to the IPCP peer address on UDP port 123.
.proc pppNtpRequest
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin

  lda pppNtpState
  cmp #PPP_NTP_STATE_REQUESTED
  beq busy
  cmp #PPP_NTP_STATE_WAITING
  beq busy
  jsr linkIsOpen
  bcc :+
  jmp linkClosed
:

  lda #PPP_NTP_STATE_REQUESTED
  sta pppNtpState
  stz pppNtpLastError
  lda #PPP_NTP_FLAG_COOKIE_VALID
  sta pppNtpFlags
  stz pppNtpVersion
  stz pppNtpLeapIndicator
  stz pppNtpStratum
  stz pppNtpPollExponent
  stz pppNtpPrecision
  m16
  lda #(PPP_NTP_COOKIE_SECONDS & $ffff)
  sta pppNtpCookieSeconds
  lda #((PPP_NTP_COOKIE_SECONDS >> 16) & $ffff)
  sta pppNtpCookieSeconds + 2
  inc pppNtpCookieFraction
  bne :+
  inc pppNtpCookieFraction + 2
:
  stz pppNtpReferenceId
  stz pppNtpReferenceId + 2
  stz pppNtpServerReceiveSeconds
  stz pppNtpServerReceiveSeconds + 2
  stz pppNtpServerReceiveFraction
  stz pppNtpServerReceiveFraction + 2
  stz pppNtpServerTransmitSeconds
  stz pppNtpServerTransmitSeconds + 2
  stz pppNtpServerTransmitFraction
  stz pppNtpServerTransmitFraction + 2
  stz pppNtpUnixSeconds
  stz pppNtpUnixSeconds + 2
  stz pppNtpDeadline
  m8
  jsr pppSnapshotEnd
  plb
  clc
  rts

busy:
  ; Reject a duplicate host request without destroying the request already
  ; queued or waiting for its correlated response.
  jsr pppSnapshotEnd
  lda #PPP_NTP_ERROR_REQUEST_BUSY
  plb
  sec
  rts
linkClosed:
  pppNtpFail PPP_NTP_ERROR_LINK_NOT_OPEN
failed:
  jsr pppSnapshotEnd
  lda pppNtpLastError
  plb
  sec
  rts

linkIsOpen:
  assert_m8_i16
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_OPENED
  bne @closed
  lda pppIpcpFlags
  and #(PPP_IPCP_FLAG_LOCAL_VALID | PPP_IPCP_FLAG_PEER_VALID)
  cmp #(PPP_IPCP_FLAG_LOCAL_VALID | PPP_IPCP_FLAG_PEER_VALID)
  bne @closed
  clc
  rts
@closed:
  sec
  rts
.endproc

; Main-loop request transmission, link cancellation, and timeout handling.
.proc pppNtpPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e
  m8
  lda pppNtpState
  cmp #PPP_NTP_STATE_REQUESTED
  beq requested
  cmp #PPP_NTP_STATE_WAITING
  bne :+
  jmp waiting
:
  jmp done

requested:
  jsr linkIsOpen
  bcc :+
  jmp linkClosed
:
  lda pppTransmitActive
  beq buildRequest
  jmp done

buildRequest:
  ldx #$0000
copyDestination:
  lda pppIpcpPeerAddress, x
  sta pppIpv4TransmitDestination, x
  inx
  cpx #$0004
  bne copyDestination

  m16
  lda #PPP_NTP_CLIENT_PORT
  sta pppUdpTransmitSourcePort
  lda #PPP_NTP_SERVER_PORT
  sta pppUdpTransmitDestinationPort
  m8
  ldx #$0000
clearPacket:
  stz pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx
  cpx #PPP_NTP_PACKET_LENGTH
  bne clearPacket
  lda #((4 << PPP_NTP_VERSION_SHIFT) | PPP_NTP_MODE_CLIENT)
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET

  m16
  lda pppNtpCookieSeconds + 2
  xba
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 40
  lda pppNtpCookieSeconds
  xba
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 42
  lda pppNtpCookieFraction + 2
  xba
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 44
  lda pppNtpCookieFraction
  xba
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 46

  ldx #PPP_NTP_PACKET_LENGTH
  m8
  jsr pppUdpBeginTransmit
  bcs transmitFailed

  jsr pppSnapshotBegin
  lda #PPP_NTP_STATE_WAITING
  sta pppNtpState
  stz pppNtpLastError
  pppIncrement32 pppNtpRequestCount
  m16
  lda frameCounter
  clc
  adc #PPP_NTP_RESPONSE_TIMEOUT_FRAMES
  sta pppNtpDeadline
  m8
  jsr pppSnapshotEnd
  jmp done

transmitFailed:
  jsr pppSnapshotBegin
  pppNtpFail PPP_NTP_ERROR_TRANSMIT_FAILED
  jsr pppSnapshotEnd
  bra done

waiting:
  jsr linkIsOpen
  bcs linkClosed
  m16
  lda frameCounter
  sec
  sbc pppNtpDeadline
  bmi done16
  m8
  jsr pppSnapshotBegin
  lda #PPP_NTP_STATE_FAILED
  sta pppNtpState
  lda #PPP_NTP_ERROR_TIMEOUT
  sta pppNtpLastError
  lda pppNtpFlags
  and #PPP_NTP_FLAG_COOKIE_VALID
  sta pppNtpFlags
  pppIncrement32 pppNtpDropCount
  pppIncrement32 pppNtpTimeoutCount
  jsr pppSnapshotEnd
  bra done

linkClosed:
  jsr pppSnapshotBegin
  pppNtpFail PPP_NTP_ERROR_LINK_NOT_OPEN
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

linkIsOpen:
  assert_m8_i16
  lda pppIpcpState
  cmp #PPP_IPCP_STATE_OPENED
  bne @closed
  lda pppIpcpFlags
  and #(PPP_IPCP_FLAG_LOCAL_VALID | PPP_IPCP_FLAG_PEER_VALID)
  cmp #(PPP_IPCP_FLAG_LOCAL_VALID | PPP_IPCP_FLAG_PEER_VALID)
  bne @closed
  clc
  rts
@closed:
  sec
  rts
.endproc

; Consume a validated UDP datagram addressed to the NTP client port. The
; caller releases the frame after return.
.proc pppNtpReceive
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppSnapshotBegin

  lda pppNtpState
  cmp #PPP_NTP_STATE_WAITING
  beq ports
  pppNtpFail PPP_NTP_ERROR_UNEXPECTED_RESPONSE
  jmp receiveDone

ports:
  m16
  lda pppUdpSourcePort
  cmp #PPP_NTP_SERVER_PORT
  bne wrongPort16
  lda pppUdpDestinationPort
  cmp #PPP_NTP_CLIENT_PORT
  bne wrongPort16
  lda pppUdpPayloadLength
  cmp #PPP_NTP_PACKET_LENGTH
  bcs source
  m8
  pppNtpFail PPP_NTP_ERROR_TRUNCATED
  jmp receiveDone

wrongPort16:
  m8
  pppNtpFail PPP_NTP_ERROR_WRONG_PORT
  jmp receiveDone

source:
  m8
  ldx #$0000
compareSource:
  lda pppIpv4SourceAddress, x
  cmp pppIpcpPeerAddress, x
  beq :+
  jmp sourceMismatch
:
  inx
  cpx #$0004
  bne compareSource

  m16
  lda pppUdpPacketOffset
  clc
  adc #PPP_UDP_HEADER_LENGTH
  sta pppNtpPacketOffset
  tax
  m8
  lda pppFrameBuffer + 0, x
  pha
  lsr
  lsr
  lsr
  and #PPP_NTP_VERSION_MASK
  sta pppNtpVersion
  cmp #$03
  beq mode
  cmp #$04
  beq mode
  pla
  pppNtpFail PPP_NTP_ERROR_UNSUPPORTED_VERSION
  jmp receiveDone

mode:
  pla
  pha
  and #PPP_NTP_MODE_MASK
  cmp #PPP_NTP_MODE_SERVER
  beq leap
  pla
  pppNtpFail PPP_NTP_ERROR_UNEXPECTED_MODE
  jmp receiveDone

leap:
  pla
  lsr
  lsr
  lsr
  lsr
  lsr
  lsr
  sta pppNtpLeapIndicator

  lda pppFrameBuffer + 1, x
  sta pppNtpStratum
  lda pppFrameBuffer + 2, x
  sta pppNtpPollExponent
  lda pppFrameBuffer + 3, x
  sta pppNtpPrecision
  ldy #$0000
copyReference:
  lda pppFrameBuffer + 12, x
  sta pppNtpReferenceId, y
  inx
  iny
  cpy #$0004
  bne copyReference
  ldx pppNtpPacketOffset

  lda pppNtpStratum
  bne :+
  jmp kissOfDeath
:
  cmp #$10
  bcc synchronized
  pppNtpFail PPP_NTP_ERROR_INVALID_STRATUM
  jmp receiveDone

synchronized:
  lda pppNtpLeapIndicator
  cmp #PPP_NTP_LEAP_UNSYNCHRONIZED
  bne cookie
  pppNtpFail PPP_NTP_ERROR_UNSYNCHRONIZED
  jmp receiveDone

cookie:
  m16
  lda pppFrameBuffer + 24, x
  xba
  cmp pppNtpCookieSeconds + 2
  beq :+
  jmp cookieMismatch16
:
  lda pppFrameBuffer + 26, x
  xba
  cmp pppNtpCookieSeconds
  beq :+
  jmp cookieMismatch16
:
  lda pppFrameBuffer + 28, x
  xba
  cmp pppNtpCookieFraction + 2
  beq :+
  jmp cookieMismatch16
:
  lda pppFrameBuffer + 30, x
  xba
  cmp pppNtpCookieFraction
  beq :+
  jmp cookieMismatch16
:

  lda pppFrameBuffer + 32, x
  xba
  sta pppNtpServerReceiveSeconds + 2
  lda pppFrameBuffer + 34, x
  xba
  sta pppNtpServerReceiveSeconds
  lda pppFrameBuffer + 36, x
  xba
  sta pppNtpServerReceiveFraction + 2
  lda pppFrameBuffer + 38, x
  xba
  sta pppNtpServerReceiveFraction
  lda pppFrameBuffer + 40, x
  xba
  sta pppNtpServerTransmitSeconds + 2
  lda pppFrameBuffer + 42, x
  xba
  sta pppNtpServerTransmitSeconds
  lda pppFrameBuffer + 44, x
  xba
  sta pppNtpServerTransmitFraction + 2
  lda pppFrameBuffer + 46, x
  xba
  sta pppNtpServerTransmitFraction

  lda pppNtpServerTransmitSeconds + 2
  cmp #((PPP_NTP_UNIX_EPOCH_OFFSET_SECONDS >> 16) & $ffff)
  bcc preUnix16
  bne convertUnix
  lda pppNtpServerTransmitSeconds
  cmp #(PPP_NTP_UNIX_EPOCH_OFFSET_SECONDS & $ffff)
  bcc preUnix16

convertUnix:
  lda pppNtpServerTransmitSeconds
  sec
  sbc #(PPP_NTP_UNIX_EPOCH_OFFSET_SECONDS & $ffff)
  sta pppNtpUnixSeconds
  lda pppNtpServerTransmitSeconds + 2
  sbc #((PPP_NTP_UNIX_EPOCH_OFFSET_SECONDS >> 16) & $ffff)
  sta pppNtpUnixSeconds + 2

  ; Commit the validated UTC timestamp through the protocol-independent
  ; clock ABI. The display clock keeps Unix seconds internally and applies
  ; JST only while decomposing its calendar fields.
  ldy pppNtpServerTransmitFraction + 2
  ldx pppNtpUnixSeconds + 2
  lda pppNtpUnixSeconds
  jsr clockSetUnixTime

  m8
  lda #PPP_NTP_STATE_RECEIVED
  sta pppNtpState
  stz pppNtpLastError
  lda #(PPP_NTP_FLAG_COOKIE_VALID | PPP_NTP_FLAG_RESPONSE_VALID | PPP_NTP_FLAG_UNIX_TIME_VALID)
  sta pppNtpFlags
  pppIncrement32 pppNtpResponseCount
  jmp receiveDone

cookieMismatch16:
  m8
  pppNtpFail PPP_NTP_ERROR_ORIGINATE_MISMATCH
  bra receiveDone
preUnix16:
  m8
  pppNtpFail PPP_NTP_ERROR_PRE_UNIX_EPOCH
  bra receiveDone
sourceMismatch:
  pppNtpFail PPP_NTP_ERROR_SOURCE_MISMATCH
  bra receiveDone
kissOfDeath:
  pppNtpFail PPP_NTP_ERROR_KISS_OF_DEATH

receiveDone:
  jsr pppSnapshotEnd
  ply
  plx
  plb
  clc
  rts
.endproc

.macro pppNtpRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; Request construction, correlated response, rejection, and timeout fixtures.
; Failure steps $99-$a1 are reserved for NTP and software-clock fixtures.
.proc pppNtpRunSelfTest
  .a8
  .i16

  m8
  i16
  phb
  phx
  phy
  setDBR $7e
  m16
  lda frameCounter
  sta pppNtpTestSavedFrameCounter
  lda frameCounter + 2
  sta pppNtpTestSavedFrameCounter + 2
  lda clockUnixSeconds
  sta pppNtpTestSavedClockSeconds
  lda clockUnixSeconds + 2
  sta pppNtpTestSavedClockSeconds + 2
  lda clockSubsecond
  sta pppNtpTestSavedClockSubsecond
  lda clockSubsecond + 2
  sta pppNtpTestSavedClockSubsecond + 2
  m8
  lda clockValid
  sta pppNtpTestSavedClockValid
  jsr prepareLink

  jsr pppNtpRequest
  bcc :+
  jmp fail99
:
  lda pppNtpState
  cmp #PPP_NTP_STATE_REQUESTED
  pppNtpRequireEqual fail99
  jsr pppNtpRequest
  bcs :+
  jmp fail99
:
  cmp #PPP_NTP_ERROR_REQUEST_BUSY
  pppNtpRequireEqual fail99
  lda pppNtpState
  cmp #PPP_NTP_STATE_REQUESTED
  pppNtpRequireEqual fail99
  m16
  jsr pppNtpPoll
  m8
  lda pppNtpState
  cmp #PPP_NTP_STATE_WAITING
  pppNtpRequireEqual fail9a
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET
  cmp #$23
  pppNtpRequireEqual fail9a
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 40
  cmp #$4e
  pppNtpRequireEqual fail9a
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 41
  cmp #$44
  pppNtpRequireEqual fail9a
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 42
  cmp #$4d
  pppNtpRequireEqual fail9a
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 43
  cmp #$24
  pppNtpRequireEqual fail9a

  jsr pppTransmitInitialize
  jsr prepareResponse
  jsr pppNtpReceive
  lda pppNtpState
  cmp #PPP_NTP_STATE_RECEIVED
  pppNtpRequireEqual fail9b
  lda pppNtpFlags
  cmp #(PPP_NTP_FLAG_COOKIE_VALID | PPP_NTP_FLAG_RESPONSE_VALID | PPP_NTP_FLAG_UNIX_TIME_VALID)
  pppNtpRequireEqual fail9b
  lda pppNtpVersion
  cmp #$04
  pppNtpRequireEqual fail9b
  lda pppNtpStratum
  cmp #$02
  pppNtpRequireEqual fail9b
  m16
  lda pppNtpServerTransmitSeconds
  cmp #$6f80
  pppNtpRequireEqual fail9b_16
  lda pppNtpServerTransmitSeconds + 2
  cmp #$e8fe
  pppNtpRequireEqual fail9b_16
  lda pppNtpUnixSeconds
  cmp #$f100
  pppNtpRequireEqual fail9c_16
  lda pppNtpUnixSeconds + 2
  cmp #$6553
  pppNtpRequireEqual fail9c_16
  lda pppNtpResponseCount
  cmp #$0001
  pppNtpRequireEqual fail9c_16
  lda clockYear
  cmp #2023
  pppNtpRequireEqual fail9c_16
  lda clockSubsecond
  cmp #$0000
  pppNtpRequireEqual fail9c_16
  lda clockSubsecond + 2
  cmp #$8000
  pppNtpRequireEqual fail9c_16
  m8
  lda clockValid
  cmp #$01
  pppNtpRequireEqual fail9c_16
  lda clockMonth
  cmp #11
  pppNtpRequireEqual fail9c_16
  lda clockDay
  cmp #15
  pppNtpRequireEqual fail9c_16
  lda clockHour
  cmp #7
  pppNtpRequireEqual fail9c_16
  lda clockMinute
  cmp #13
  pppNtpRequireEqual fail9c_16
  lda clockSecond
  cmp #20
  pppNtpRequireEqual fail9c_16

  ; Crossing a second boundary must not let display formatting corrupt the X
  ; frame-loop counter. From fraction $80000000, 60 nominal NTSC frames yield
  ; one whole second and fraction $7F943F2C.
  m16
  ldx #60
  jsr clockAdvanceFrames
  lda clockUnixSeconds
  cmp #$f101
  pppNtpRequireEqual faila1_16
  lda clockUnixSeconds + 2
  cmp #$6553
  pppNtpRequireEqual faila1_16
  lda clockSubsecond
  cmp #$3f2c
  pppNtpRequireEqual faila1_16
  lda clockSubsecond + 2
  cmp #$7f94
  pppNtpRequireEqual faila1_16
  m8
  lda clockSecond
  cmp #21
  pppNtpRequireEqual faila1

  ; A stale or forged response cannot satisfy a new waiting request.
  m8
  lda #PPP_NTP_STATE_WAITING
  sta pppNtpState
  inc pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 31
  jsr pppNtpReceive
  lda pppNtpLastError
  cmp #PPP_NTP_ERROR_ORIGINATE_MISMATCH
  pppNtpRequireEqual fail9d

  ; Stratum zero preserves the four-byte Kiss-o'-Death code.
  jsr prepareResponse
  lda #PPP_NTP_STATE_WAITING
  sta pppNtpState
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 1
  lda #$52
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 12
  lda #$41
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 13
  lda #$54
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 14
  lda #$45
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 15
  jsr pppNtpReceive
  lda pppNtpLastError
  cmp #PPP_NTP_ERROR_KISS_OF_DEATH
  pppNtpRequireEqual fail9e
  lda pppNtpReferenceId + 3
  cmp #$45
  pppNtpRequireEqual fail9e

  ; A transmitted request expires at its low-16-bit frame deadline.
  jsr pppNtpRequest
  bcc :+
  jmp fail9f
:
  m16
  jsr pppNtpPoll
  lda pppNtpDeadline
  sta frameCounter
  jsr pppNtpPoll
  m8
  lda pppNtpLastError
  cmp #PPP_NTP_ERROR_TIMEOUT
  pppNtpRequireEqual fail9f
  m16
  lda pppNtpTimeoutCount
  cmp #$0001
  bne fail9f_16

  ; Requests below IPCP Opened are rejected synchronously.
  m8
  stz pppIpcpState
  jsr pppNtpRequest
  bcs :+
  jmp faila0
:
  lda pppNtpLastError
  cmp #PPP_NTP_ERROR_LINK_NOT_OPEN
  pppNtpRequireEqual faila0

  jsr cleanup
  lda #$00
  clc
  bra return

fail99:
  lda #$99
  bra fail
fail9a:
  lda #$9a
  bra fail
fail9b_16:
  m8
fail9b:
  lda #$9b
  bra fail
fail9c_16:
  m8
  lda #$9c
  bra fail
fail9d:
  lda #$9d
  bra fail
fail9e:
  lda #$9e
  bra fail
fail9f_16:
  m8
fail9f:
  lda #$9f
  bra fail
faila0:
  lda #$a0
  bra fail
faila1_16:
  m8
faila1:
  lda #$a1
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

prepareLink:
  assert_m8_i16
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppUdpInitialize
  jsr pppNtpInitialize
  lda #PPP_IPCP_STATE_OPENED
  sta pppIpcpState
  lda #(PPP_IPCP_FLAG_LOCAL_VALID | PPP_IPCP_FLAG_PEER_VALID)
  sta pppIpcpFlags
  lda #$0a
  sta pppIpcpPeerAddress + 0
  lda #$18
  sta pppIpcpPeerAddress + 1
  stz pppIpcpPeerAddress + 2
  lda #$01
  sta pppIpcpPeerAddress + 3
  rts

prepareResponse:
  assert_m8_i16
  lda #PPP_UDP_FLAG_VALID
  sta pppUdpFlags
  m16
  lda #PPP_NTP_SERVER_PORT
  sta pppUdpSourcePort
  lda #PPP_NTP_CLIENT_PORT
  sta pppUdpDestinationPort
  lda #PPP_NTP_PACKET_LENGTH
  sta pppUdpPayloadLength
  lda #(PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_IPV4_MINIMUM_HEADER_LENGTH)
  sta pppUdpPacketOffset
  m8
  lda #$0a
  sta pppIpv4SourceAddress + 0
  lda #$18
  sta pppIpv4SourceAddress + 1
  stz pppIpv4SourceAddress + 2
  lda #$01
  sta pppIpv4SourceAddress + 3
  ldx #$0000
@clear:
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx
  cpx #PPP_NTP_PACKET_LENGTH
  bne @clear
  lda #$24
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 0
  lda #$02
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 1
  lda #$06
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 2
  lda #$ec
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 3
  lda #$47
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 12
  lda #$50
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 13
  lda #$53
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 14
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 15

  ; Originate Timestamp echoes the request cookie.
  ldx #$0000
@cookie:
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 40, x
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 24, x
  inx
  cpx #$0008
  bne @cookie

  ; Receive $E8FE6F7F.F0000000, Transmit $E8FE6F80.80000000.
  lda #$e8
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 32
  lda #$fe
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 33
  lda #$6f
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 34
  lda #$7f
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 35
  lda #$f0
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 36
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 37
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 38
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 39
  lda #$e8
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 40
  lda #$fe
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 41
  lda #$6f
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 42
  lda #$80
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 43
  sta pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 44
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 45
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 46
  stz pppFrameBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 47
  rts

cleanup:
  assert_m8_i16
  m16
  lda pppNtpTestSavedFrameCounter
  sta frameCounter
  lda pppNtpTestSavedFrameCounter + 2
  sta frameCounter + 2
  lda #$0000
  m8
  lda pppNtpTestSavedClockValid
  m16
  and #$00ff
  beq @restoreInvalidClock

  ldy pppNtpTestSavedClockSubsecond + 2
  ldx pppNtpTestSavedClockSeconds + 2
  lda pppNtpTestSavedClockSeconds
  jsr clockSetUnixTime
  lda pppNtpTestSavedClockSubsecond
  sta clockSubsecond
  lda pppNtpTestSavedClockSubsecond + 2
  sta clockSubsecond + 2
  bra @clockRestored

@restoreInvalidClock:
  jsr clockInitialize
@clockRestored:
  m8
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppUdpInitialize
  jsr pppNtpInitialize
  rts
.endproc
