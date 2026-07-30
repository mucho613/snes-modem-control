.include "../macro/utility.asm"
.include "constants.inc"

.code

.import frameCounter
.import pppSnapshotBegin, pppSnapshotEnd
.import pppFrameBuffer, pppTransmitActive, pppTransmitBuffer
.import pppTransmitInitialize
.import pppIpcpState, pppIpcpFlags, pppIpcpLocalAddress
.import pppIpcpInitialize
.import pppIpv4SourceAddress, pppIpv4TransmitDestination
.import pppIpv4Initialize
.import pppUdpSourcePort, pppUdpDestinationPort
.import pppUdpPayloadLength, pppUdpPacketOffset
.import pppUdpTransmitSourcePort, pppUdpTransmitDestinationPort
.import pppUdpBeginTransmit, pppUdpInitialize
.import pppDnsState, pppDnsLastError, pppDnsFlags, pppDnsResponseCode
.import pppDnsResolver, pppDnsTransactionId, pppDnsAnswerCount
.import pppDnsAnswerAddress, pppDnsDeadline, pppDnsSentFrame, pppDnsRttFrames
.import pppDnsQueryCount, pppDnsResponseCount
.import pppDnsDropCount, pppDnsTimeoutCount
.import pppDnsQueryName, pppDnsQueryNameLength
.import pppDnsPacketOffset, pppDnsPacketEnd, pppDnsCursor
.import pppDnsRecordRemaining, pppDnsDataLength
.import pppDnsQueryCursor, pppDnsLabelPosition, pppDnsLabelLength
.import pppDnsTestSavedFrameCounter

.export pppDnsInitialize, pppDnsRequest, pppDnsPoll, pppDnsReceive
.export pppDnsRunSelfTest

.macro pppDnsFail error
  lda #PPP_DNS_STATE_FAILED
  sta pppDnsState
  lda #error
  sta pppDnsLastError
  stz pppDnsFlags
  pppIncrement32 pppDnsDropCount
.endmacro

.proc pppDnsInitialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppDnsState
  stz pppDnsLastError
  stz pppDnsFlags
  stz pppDnsResponseCode
  stz pppDnsResolver + 0
  stz pppDnsResolver + 1
  stz pppDnsResolver + 2
  stz pppDnsResolver + 3
  stz pppDnsAnswerAddress + 0
  stz pppDnsAnswerAddress + 1
  stz pppDnsAnswerAddress + 2
  stz pppDnsAnswerAddress + 3
  stz pppDnsQueryNameLength
  stz pppDnsLabelLength
  m16
  lda #PPP_DNS_INITIAL_TRANSACTION_ID
  sta pppDnsTransactionId
  stz pppDnsAnswerCount
  stz pppDnsDeadline
  stz pppDnsSentFrame
  stz pppDnsRttFrames
  stz pppDnsQueryCount
  stz pppDnsQueryCount + 2
  stz pppDnsResponseCount
  stz pppDnsResponseCount + 2
  stz pppDnsDropCount
  stz pppDnsDropCount + 2
  stz pppDnsTimeoutCount
  stz pppDnsTimeoutCount + 2
  stz pppDnsPacketOffset
  stz pppDnsPacketEnd
  stz pppDnsCursor
  stz pppDnsRecordRemaining
  stz pppDnsDataLength
  stz pppDnsQueryCursor
  stz pppDnsLabelPosition
  m8
  plb
  rts
.endproc

; Queue an A query. The mailbox has already copied the resolver, raw ASCII
; name, and name length into the DNS state. Carry set returns an error in A.
.proc pppDnsRequest
  .a8
  .i16

  phb
  phx
  setDBR $7e
  lda pppDnsState
  cmp #PPP_DNS_STATE_REQUESTED
  beq busy
  cmp #PPP_DNS_STATE_WAITING
  beq busy
  jsr linkIsOpen
  bcs linkClosed
  jsr validateName
  bcs invalidName

  jsr pppSnapshotBegin
  lda #PPP_DNS_STATE_REQUESTED
  sta pppDnsState
  stz pppDnsLastError
  stz pppDnsFlags
  stz pppDnsResponseCode
  stz pppDnsAnswerAddress + 0
  stz pppDnsAnswerAddress + 1
  stz pppDnsAnswerAddress + 2
  stz pppDnsAnswerAddress + 3
  m16
  inc pppDnsTransactionId
  bne transactionReady
  inc pppDnsTransactionId
transactionReady:
  stz pppDnsAnswerCount
  stz pppDnsDeadline
  stz pppDnsSentFrame
  stz pppDnsRttFrames
  m8
  jsr pppSnapshotEnd
  plx
  plb
  clc
  rts

busy:
  lda #PPP_DNS_ERROR_REQUEST_BUSY
  plx
  plb
  sec
  rts

invalidName:
  jsr pppSnapshotBegin
  pppDnsFail PPP_DNS_ERROR_INVALID_NAME
  jsr pppSnapshotEnd
  lda pppDnsLastError
  plx
  plb
  sec
  rts

linkClosed:
  jsr pppSnapshotBegin
  pppDnsFail PPP_DNS_ERROR_LINK_NOT_OPEN
  jsr pppSnapshotEnd
  lda pppDnsLastError
  plx
  plb
  sec
  rts

linkIsOpen:
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

validateName:
  lda pppDnsQueryNameLength
  beq nameInvalid
  cmp #(PPP_DNS_MAXIMUM_NAME_LENGTH + 1)
  bcs nameInvalid
  tax
  dex
  lda pppDnsQueryName
  cmp #'.'
  beq nameInvalid
  lda pppDnsQueryName, x
  cmp #'.'
  beq nameInvalid

  ldx #$0000
  stz pppDnsLabelLength
validateCharacter:
  lda pppDnsQueryName, x
  cmp #'.'
  beq dot
  cmp #'-'
  beq characterValid
  cmp #'0'
  bcc nameInvalid
  cmp #('9' + 1)
  bcc characterValid
  cmp #'A'
  bcc nameInvalid
  cmp #('Z' + 1)
  bcc characterValid
  cmp #'a'
  bcc nameInvalid
  cmp #('z' + 1)
  bcs nameInvalid
characterValid:
  inc pppDnsLabelLength
  bra nextCharacter
dot:
  lda pppDnsLabelLength
  beq nameInvalid
  stz pppDnsLabelLength
nextCharacter:
  inx
  cpx #PPP_DNS_MAXIMUM_NAME_LENGTH
  beq nameInvalid
  txa
  cmp pppDnsQueryNameLength
  bcc validateCharacter
  lda pppDnsLabelLength
  beq nameInvalid
  clc
  rts
nameInvalid:
  sec
  rts
.endproc

.proc pppDnsPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e
  m8
  lda pppDnsState
  cmp #PPP_DNS_STATE_REQUESTED
  beq requested
  cmp #PPP_DNS_STATE_WAITING
  beq :+
  jmp pollDone
:
  jmp waiting

requested:
  jsr pppDnsLinkIsOpen
  bcc :+
  jmp linkClosed
:
  lda pppTransmitActive
  beq :+
  jmp pollDone
:

  ldx #$0000
copyDestination:
  lda pppDnsResolver, x
  sta pppIpv4TransmitDestination, x
  inx
  cpx #$0004
  bne copyDestination

  m16
  lda #PPP_DNS_CLIENT_PORT
  sta pppUdpTransmitSourcePort
  lda #PPP_DNS_SERVER_PORT
  sta pppUdpTransmitDestinationPort
  m8
  ldx #$0000
clearHeader:
  stz pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx
  cpx #PPP_DNS_HEADER_LENGTH
  bne clearHeader
  m16
  lda pppDnsTransactionId
  xba
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 0
  lda #$0001
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 2
  lda #$0100
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 4
  stz pppDnsQueryCursor
  lda #PPP_DNS_HEADER_LENGTH
  sta pppDnsLabelPosition
  tax
  inx
  m8
  stz pppDnsLabelLength

encodeName:
  m16
  ldy pppDnsQueryCursor
  m8
  lda pppDnsQueryName, y
  cmp #'.'
  beq encodeDot
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx
  inc pppDnsLabelLength
  bra encodeNext

encodeDot:
  m16
  stx pppDnsCursor
  ldy pppDnsLabelPosition
  m8
  lda pppDnsLabelLength
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, y
  stz pppDnsLabelLength
  m16
  ldx pppDnsCursor
  stx pppDnsLabelPosition
  inx
  m8
encodeNext:
  m16
  inc pppDnsQueryCursor
  lda pppDnsQueryCursor
  m8
  cmp pppDnsQueryNameLength
  bcc encodeName

  m16
  stx pppDnsCursor
  ldy pppDnsLabelPosition
  m8
  lda pppDnsLabelLength
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, y
  m16
  ldx pppDnsCursor
  m8
  stz pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx
  stz pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx
  lda #PPP_DNS_TYPE_A
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx
  stz pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx
  lda #PPP_DNS_CLASS_IN
  sta pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET, x
  inx

  jsr pppUdpBeginTransmit
  bcs transmitFailed

  jsr pppSnapshotBegin
  lda #PPP_DNS_STATE_WAITING
  sta pppDnsState
  stz pppDnsLastError
  stz pppDnsFlags
  pppIncrement32 pppDnsQueryCount
  m16
  lda frameCounter
  sta pppDnsSentFrame
  clc
  adc #PPP_DNS_RESPONSE_TIMEOUT_FRAMES
  sta pppDnsDeadline
  m8
  jsr pppSnapshotEnd
  jmp pollDone

transmitFailed:
  jsr pppSnapshotBegin
  pppDnsFail PPP_DNS_ERROR_TRANSMIT_FAILED
  jsr pppSnapshotEnd
  bra pollDone

waiting:
  jsr pppDnsLinkIsOpen
  bcs linkClosed
  m16
  lda frameCounter
  sec
  sbc pppDnsDeadline
  bmi pollDone16
  m8
  jsr pppSnapshotBegin
  pppDnsFail PPP_DNS_ERROR_TIMEOUT
  pppIncrement32 pppDnsTimeoutCount
  jsr pppSnapshotEnd
  bra pollDone

linkClosed:
  jsr pppSnapshotBegin
  pppDnsFail PPP_DNS_ERROR_LINK_NOT_OPEN
  jsr pppSnapshotEnd
  bra pollDone

pollDone16:
  m8
pollDone:
  mi16
  ply
  plx
  plb
  pla
  rts
.endproc

.proc pppDnsLinkIsOpen
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

; Consume one checksum-validated UDP datagram addressed to the DNS client port.
; Candidate source/port/ID mismatches leave the current query waiting.
.proc pppDnsReceive
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  lda pppDnsState
  cmp #PPP_DNS_STATE_WAITING
  beq receiveCandidate
  jmp receiveDone

receiveCandidate:
  jsr pppSnapshotBegin
  m16
  lda pppUdpSourcePort
  cmp #PPP_DNS_SERVER_PORT
  beq :+
  jmp wrongPort16
:
  lda pppUdpDestinationPort
  cmp #PPP_DNS_CLIENT_PORT
  beq :+
  jmp wrongPort16
:
  m8
  ldx #$0000
compareSource:
  lda pppIpv4SourceAddress, x
  cmp pppDnsResolver, x
  beq :+
  jmp sourceMismatch
:
  inx
  cpx #$0004
  bne compareSource

  m16
  lda pppUdpPayloadLength
  cmp #PPP_DNS_HEADER_LENGTH
  bcs :+
  jmp truncated16
:
  lda pppUdpPacketOffset
  clc
  adc #PPP_UDP_HEADER_LENGTH
  sta pppDnsPacketOffset
  tax
  clc
  adc pppUdpPayloadLength
  sta pppDnsPacketEnd

  lda pppFrameBuffer + 0, x
  xba
  cmp pppDnsTransactionId
  beq :+
  jmp identifierMismatch16
:
  m8
  lda pppFrameBuffer + 2, x
  bmi responseBitSet
  lda #PPP_DNS_ERROR_NOT_RESPONSE
  jmp correlatedFailure
responseBitSet:
  and #$78
  beq opcodeValid
  lda #PPP_DNS_ERROR_UNSUPPORTED_OPCODE
  jmp correlatedFailure
opcodeValid:
  lda pppFrameBuffer + 2, x
  and #$02
  beq notTruncated
  lda #PPP_DNS_ERROR_TRUNCATED_RESPONSE
  jmp correlatedFailure
notTruncated:
  lda pppFrameBuffer + 3, x
  and #$0f
  sta pppDnsResponseCode
  beq responseCodeValid
  lda #PPP_DNS_ERROR_RESPONSE_CODE
  jmp correlatedFailure
responseCodeValid:

  m16
  lda pppFrameBuffer + 4, x
  xba
  bne :+
  jmp noQuestion16
:
  sta pppDnsRecordRemaining
  lda pppFrameBuffer + 6, x
  xba
  sta pppDnsAnswerCount
  bne :+
  jmp noAnswer16
:
  txa
  clc
  adc #PPP_DNS_HEADER_LENGTH
  tax

questionLoop:
  jsr skipName
  bcc :+
  jmp malformedName16
:
  lda #$0004
  jsr requireBytes
  bcc :+
  jmp truncated16
:
  txa
  clc
  adc #$0004
  tax
  dec pppDnsRecordRemaining
  bne questionLoop

  lda pppDnsAnswerCount
  sta pppDnsRecordRemaining
answerLoop:
  jsr skipName
  bcc :+
  jmp malformedName16
:
  lda #$000a
  jsr requireBytes
  bcc :+
  jmp truncated16
:
  m8
  stz pppDnsLabelLength
  m16
  lda pppFrameBuffer + 0, x
  xba
  cmp #PPP_DNS_TYPE_A
  bne readDataLength
  lda pppFrameBuffer + 2, x
  xba
  cmp #PPP_DNS_CLASS_IN
  bne readDataLength
  m8
  inc pppDnsLabelLength
  m16
readDataLength:
  lda pppFrameBuffer + 8, x
  xba
  sta pppDnsDataLength
  txa
  clc
  adc #$000a
  tax
  lda pppDnsDataLength
  jsr requireBytes
  bcc :+
  jmp truncated16
:
  m8
  lda pppDnsLabelLength
  beq skipRecord
  m16
  lda pppDnsDataLength
  cmp #$0004
  bne skipRecord16
  m8
  ldy #$0000
copyAnswer:
  lda pppFrameBuffer, x
  sta pppDnsAnswerAddress, y
  inx
  iny
  cpy #$0004
  bne copyAnswer

  lda #PPP_DNS_STATE_RECEIVED
  sta pppDnsState
  stz pppDnsLastError
  lda #PPP_DNS_FLAG_RESPONSE_VALID
  sta pppDnsFlags
  pppIncrement32 pppDnsResponseCount
  m16
  lda frameCounter
  sec
  sbc pppDnsSentFrame
  sta pppDnsRttFrames
  m8
  jsr pppSnapshotEnd
  bra receiveDone

skipRecord16:
  m8
skipRecord:
  m16
  txa
  clc
  adc pppDnsDataLength
  tax
  dec pppDnsRecordRemaining
  beq :+
  jmp answerLoop
:
  m8
  lda #PPP_DNS_ERROR_NO_IPV4_ANSWER
  bra correlatedFailure

wrongPort16:
  m8
  lda #PPP_DNS_ERROR_WRONG_PORT
  bra candidateRejected
sourceMismatch:
  lda #PPP_DNS_ERROR_SOURCE_MISMATCH
  bra candidateRejected
identifierMismatch16:
  m8
  lda #PPP_DNS_ERROR_IDENTIFIER_MISMATCH
candidateRejected:
  sta pppDnsLastError
  pppIncrement32 pppDnsDropCount
  jsr pppSnapshotEnd
  bra receiveDone

truncated16:
  m8
  lda #PPP_DNS_ERROR_TRUNCATED
  bra correlatedFailure
noQuestion16:
  m8
  lda #PPP_DNS_ERROR_NO_QUESTION
  bra correlatedFailure
noAnswer16:
  m8
  lda #PPP_DNS_ERROR_NO_ANSWER
  bra correlatedFailure
malformedName16:
  m8
  lda #PPP_DNS_ERROR_MALFORMED_NAME
correlatedFailure:
  sta pppDnsLastError
  lda #PPP_DNS_STATE_FAILED
  sta pppDnsState
  stz pppDnsFlags
  pppIncrement32 pppDnsDropCount
  jsr pppSnapshotEnd

receiveDone:
  ply
  plx
  plb
  clc
  rts

; X is a DNS message-relative name cursor expressed as a frame-buffer offset.
; A16 is returned; carry set means malformed or truncated.
skipName:
  assert_m16_i16
nameOctet:
  lda #$0001
  jsr requireBytes
  bcs nameError
  m8
  lda pppFrameBuffer, x
  beq nameEnd
  pha
  and #$c0
  beq plainLabel
  cmp #$c0
  beq compressedName
  pla
  m16
  sec
  rts
compressedName:
  pla
  m16
  lda #$0002
  jsr requireBytes
  bcs nameError
  lda pppFrameBuffer, x
  xba
  and #$3fff
  cmp pppUdpPayloadLength
  bcs nameError
  inx
  inx
  clc
  rts
plainLabel:
  pla
  m16
  and #$00ff
  inc
  jsr requireBytes
  bcs nameError
  txa
  clc
  adc pppDnsDataLength
  tax
  bra nameOctet
nameError:
  sec
  rts
nameEnd:
  inx
  m16
  clc
  rts

; A16 bytes must be available starting at X. X is preserved.
requireBytes:
  assert_m16_i16
  sta pppDnsDataLength
  txa
  clc
  adc pppDnsDataLength
  cmp pppDnsPacketEnd
  beq available
  bcc available
  sec
  rts
available:
  clc
  rts
.endproc

.macro pppDnsRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

; Query construction, correlation, parser, timeout, and phase-gating fixtures.
; Failure steps $a8-$af are reserved for DNS.
.proc pppDnsRunSelfTest
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
  sta pppDnsTestSavedFrameCounter
  lda frameCounter + 2
  sta pppDnsTestSavedFrameCounter + 2
  m8
  jsr prepareLinkAndQuery
  jsr pppDnsRequest
  bcc :+
  jmp faila8
:
  lda pppDnsState
  cmp #PPP_DNS_STATE_REQUESTED
  pppDnsRequireEqual faila8
  m16
  lda pppDnsTransactionId
  cmp #$4e44
  pppDnsRequireEqual faila8_16
  m8
  lda #$01
  sta pppTransmitActive
  m16
  jsr pppDnsPoll
  m8
  lda pppDnsState
  cmp #PPP_DNS_STATE_REQUESTED
  pppDnsRequireEqual faila9

  jsr pppTransmitInitialize
  m16
  lda #$0200
  sta frameCounter
  jsr pppDnsPoll
  m8
  lda pppDnsState
  cmp #PPP_DNS_STATE_WAITING
  pppDnsRequireEqual failaa
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 0
  cmp #$4e
  pppDnsRequireEqual failaa
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 1
  cmp #$44
  pppDnsRequireEqual failaa
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 12
  cmp #$07
  pppDnsRequireEqual failaa
  lda pppTransmitBuffer + PPP_UDP_TRANSMIT_PAYLOAD_OFFSET + 20
  cmp #$03
  pppDnsRequireEqual failaa

  jsr prepareResponse
  m16
  lda pppDnsSentFrame
  clc
  adc #$0009
  sta frameCounter
  m8
  jsr pppDnsReceive
  lda pppDnsState
  cmp #PPP_DNS_STATE_RECEIVED
  pppDnsRequireEqual failab
  lda pppDnsAnswerAddress + 0
  cmp #93
  pppDnsRequireEqual failab
  lda pppDnsAnswerAddress + 3
  cmp #34
  pppDnsRequireEqual failab
  m16
  lda pppDnsRttFrames
  cmp #$0009
  beq @rttAccepted
  cmp #$000a
  pppDnsRequireEqual failab_16
@rttAccepted:
  m8
  jsr pppTransmitInitialize
  jsr pppDnsRequest
  bcc :+
  jmp failac
:
  m16
  jsr pppDnsPoll
  m8
  jsr prepareResponse
  inc pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 1
  jsr pppDnsReceive
  lda pppDnsState
  cmp #PPP_DNS_STATE_WAITING
  pppDnsRequireEqual failac
  lda pppDnsLastError
  cmp #PPP_DNS_ERROR_IDENTIFIER_MISMATCH
  pppDnsRequireEqual failac

  jsr prepareResponse
  lda #$83
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 3
  jsr pppDnsReceive
  lda pppDnsState
  cmp #PPP_DNS_STATE_FAILED
  pppDnsRequireEqual failad
  lda pppDnsLastError
  cmp #PPP_DNS_ERROR_RESPONSE_CODE
  pppDnsRequireEqual failad
  lda pppDnsResponseCode
  cmp #$03
  pppDnsRequireEqual failad

  jsr pppDnsInitialize
  jsr prepareLinkAndQuery
  jsr pppDnsRequest
  bcc :+
  jmp failae
:
  m16
  jsr pppDnsPoll
  lda pppDnsDeadline
  sta frameCounter
  jsr pppDnsPoll
  m8
  lda pppDnsState
  cmp #PPP_DNS_STATE_FAILED
  pppDnsRequireEqual failae
  lda pppDnsLastError
  cmp #PPP_DNS_ERROR_TIMEOUT
  pppDnsRequireEqual failae

  jsr pppDnsInitialize
  jsr prepareLinkAndQuery
  lda #'.'
  sta pppDnsQueryName
  jsr pppDnsRequest
  bcc failaf
  cmp #PPP_DNS_ERROR_INVALID_NAME
  pppDnsRequireEqual failaf
  jsr pppIpcpInitialize
  jsr prepareQuery
  jsr pppDnsRequest
  bcc failaf
  cmp #PPP_DNS_ERROR_LINK_NOT_OPEN
  pppDnsRequireEqual failaf

  m16
  jsr cleanup
  m8
  lda #$00
  clc
  bra selfTestReturn

faila8_16:
  m8
faila8:
  lda #$a8
  bra selfTestFail
faila9:
  lda #$a9
  bra selfTestFail
failaa:
  lda #$aa
  bra selfTestFail
failab_16:
  m8
failab:
  lda #$ab
  bra selfTestFail
failac:
  lda #$ac
  bra selfTestFail
failad:
  lda #$ad
  bra selfTestFail
failae:
  lda #$ae
  bra selfTestFail
failaf:
  lda #$af
selfTestFail:
  pha
  m16
  jsr cleanup
  m8
  pla
  sec
selfTestReturn:
  ply
  plx
  plb
  rts

prepareLinkAndQuery:
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppUdpInitialize
  jsr pppDnsInitialize
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
prepareQuery:
  lda #$01
  sta pppDnsResolver + 0
  sta pppDnsResolver + 1
  sta pppDnsResolver + 2
  sta pppDnsResolver + 3
  lda #11
  sta pppDnsQueryNameLength
  ldx #$0000
copyQueryName:
  lda f:exampleName, x
  sta pppDnsQueryName, x
  inx
  cpx #11
  bne copyQueryName
  rts

prepareResponse:
  ldx #$0000
copyResponse:
  lda f:exampleResponse, x
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH, x
  inx
  cpx #(exampleResponseEnd - exampleResponse)
  bne copyResponse
  lda pppDnsTransactionId + 1
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 0
  lda pppDnsTransactionId
  sta pppFrameBuffer + PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH + PPP_UDP_HEADER_LENGTH + 1
  ldx #$0000
copyResponseSource:
  lda pppDnsResolver, x
  sta pppIpv4SourceAddress, x
  inx
  cpx #$0004
  bne copyResponseSource
  m16
  lda #PPP_DNS_SERVER_PORT
  sta pppUdpSourcePort
  lda #PPP_DNS_CLIENT_PORT
  sta pppUdpDestinationPort
  lda #(PPP_IPV4_FRAME_OFFSET + PPP_IPV4_MINIMUM_HEADER_LENGTH)
  sta pppUdpPacketOffset
  lda #(exampleResponseEnd - exampleResponse)
  sta pppUdpPayloadLength
  m8
  rts

cleanup:
  lda pppDnsTestSavedFrameCounter
  sta frameCounter
  lda pppDnsTestSavedFrameCounter + 2
  sta frameCounter + 2
  m8
  jsr pppTransmitInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppUdpInitialize
  jsr pppDnsInitialize
  m16
  rts
.endproc

.data
exampleName:
  .byte "example.com"

exampleResponse:
  .byte $4e, $44, $81, $80, $00, $01, $00, $01, $00, $00, $00, $00
  .byte $07, "example", $03, "com", $00, $00, $01, $00, $01
  .byte $c0, $0c, $00, $01, $00, $01, $00, $00, $00, $3c, $00, $04
  .byte 93, 184, 216, 34
exampleResponseEnd:
