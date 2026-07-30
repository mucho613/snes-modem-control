; Human-facing network dashboards selected by statusPage.
;
; This adapter owns only the three application pages and their WRAM text.
; It does not touch PPU registers, screenMode, or the raw terminal.

STATUS_PAGE_NTP = $01
STATUS_PAGE_DNS = $02
STATUS_PAGE_ICMP = $03

NETWORK_VALUE_COLUMN = 7
NETWORK_LONG_VALUE_COLUMN = 8
NETWORK_COUNTER_COLUMN = 10

.macro networkWriteImmediate row, column, text
  .repeat .strlen(text), index
    lda #.strat(text, index)
    sta statusTileBuffer + (row * TERMINAL_COLUMNS) + column + index
  .endrepeat
.endmacro

.macro networkWriteAtX text
  .repeat .strlen(text), index
    lda #.strat(text, index)
    sta statusTileBuffer, x
    inx
  .endrepeat
.endmacro

.macro networkClearFrom row, column
  ldx #(row * TERMINAL_COLUMNS) + column
  lda #' '
:
  sta statusTileBuffer, x
  inx
  cpx #((row + 1) * TERMINAL_COLUMNS)
  bne :-
.endmacro

.macro networkJumpIfEqual target
  bne :+
  jmp target
:
.endmacro

.macro networkDecimalDigit divisor
  lda statusFormatValue
  ldy #$0000
:
  cmp #divisor
  bcc :+
  sec
  sbc #divisor
  iny
  bra :-
:
  sta statusFormatValue
  cpy #$0000
  bne :+
  sep #$20
  .a8
  lda statusFormatStarted
  beq :++
  rep #$20
  .a16
:
  sep #$20
  .a8
  tya
  clc
  adc #'0'
  sta statusTileBuffer, x
  inx
  lda #$01
  sta statusFormatStarted
:
  rep #$20
  .a16
.endmacro

.segment "DATA"

.import statusPage, statusTileBuffer
.import statusFormatValue, statusFormatStarted
.import clockDisplayText

.import pppNtpState, pppNtpLastError, pppNtpVersion, pppNtpStratum
.import pppNtpReferenceId, pppNtpRequestCount, pppNtpResponseCount
.import pppNtpTimeoutCount

.import pppDnsState, pppDnsLastError, pppDnsFlags
.import pppDnsResolver, pppDnsTransactionId, pppDnsAnswerCount
.import pppDnsAnswerAddress, pppDnsRttFrames
.import pppDnsQueryCount, pppDnsResponseCount, pppDnsDropCount
.import pppDnsTimeoutCount, pppDnsQueryName, pppDnsQueryNameLength

.import pppIcmpRequestState, pppIcmpRequestLastError, pppIcmpRequestFlags
.import pppIcmpRequestDestination, pppIcmpRequestIdentifier
.import pppIcmpRequestSequence, pppIcmpRequestRttFrames
.import pppIcmpRequestCount, pppIcmpRequestResponseCount
.import pppIcmpRequestDropCount, pppIcmpRequestTimeoutCount
.import pppIcmpInboundState, pppIcmpInboundLastError, pppIcmpInboundFlags
.import pppIcmpInboundSource, pppIcmpInboundIdentifier
.import pppIcmpInboundSequence, pppIcmpInboundPayloadLength
.import pppIcmpEchoRequestCount, pppIcmpInboundReplyCount
.import pppIcmpInboundDropCount

.export applicationStatusInitialize, applicationStatusPoll

.proc applicationStatusInitialize
  .a8
  .i16

  lda statusPage
  cmp #STATUS_PAGE_NTP
  networkJumpIfEqual @ntp
  cmp #STATUS_PAGE_DNS
  networkJumpIfEqual @dns

  networkWriteImmediate 0, 0, "APP    ICMP"
  networkWriteImmediate 2, 0, "OUTBOUND"
  networkWriteImmediate 3, 0, "STATE  "
  networkWriteImmediate 4, 0, "PEER   "
  networkWriteImmediate 5, 0, "ID     "
  networkWriteImmediate 6, 0, "SEQ    "
  networkWriteImmediate 7, 0, "RTT    "
  networkWriteImmediate 8, 0, "ERROR  "
  networkWriteImmediate 10, 0, "REQUESTS "
  networkWriteImmediate 11, 0, "RESPONSES"
  networkWriteImmediate 12, 0, "DROPS    "
  networkWriteImmediate 13, 0, "TIMEOUTS "
  networkWriteImmediate 15, 0, "INBOUND"
  networkWriteImmediate 16, 0, "STATE  "
  networkWriteImmediate 17, 0, "SOURCE "
  networkWriteImmediate 18, 0, "ID     "
  networkWriteImmediate 19, 0, "SEQ    "
  networkWriteImmediate 20, 0, "BYTES  "
  networkWriteImmediate 21, 0, "REQUESTS "
  networkWriteImmediate 22, 0, "REPLIES  "
  networkWriteImmediate 23, 0, "DROPS    "
  networkWriteImmediate 24, 0, "ERROR  "
  rtl

@ntp:
  networkWriteImmediate 0, 0, "APP    NTP"
  networkWriteImmediate 2, 0, "STATE  "
  networkWriteImmediate 3, 0, "TIME   "
  networkWriteImmediate 4, 0, "ERROR  "
  networkWriteImmediate 6, 0, "VERSION"
  networkWriteImmediate 7, 0, "STRATUM"
  networkWriteImmediate 8, 0, "REF ID "
  networkWriteImmediate 10, 0, "REQUESTS "
  networkWriteImmediate 11, 0, "RESPONSES"
  networkWriteImmediate 12, 0, "TIMEOUTS "
  rtl

@dns:
  networkWriteImmediate 0, 0, "APP    DNS"
  networkWriteImmediate 2, 0, "STATE  "
  networkWriteImmediate 3, 0, "HOST   "
  networkWriteImmediate 4, 0, "RESOLVR"
  networkWriteImmediate 5, 0, "A      "
  networkWriteImmediate 6, 0, "ANSWERS"
  networkWriteImmediate 7, 0, "TX ID  "
  networkWriteImmediate 8, 0, "RTT    "
  networkWriteImmediate 9, 0, "ERROR  "
  networkWriteImmediate 11, 0, "REQUESTS "
  networkWriteImmediate 12, 0, "RESPONSES"
  networkWriteImmediate 13, 0, "DROPS    "
  networkWriteImmediate 14, 0, "TIMEOUTS "
  rtl
.endproc

.proc applicationStatusPoll
  .a8
  .i16

  lda statusPage
  cmp #STATUS_PAGE_NTP
  networkJumpIfEqual @ntp
  cmp #STATUS_PAGE_DNS
  networkJumpIfEqual @dns
  jmp @icmp

@ntp:
  networkClearFrom 2, NETWORK_VALUE_COLUMN
  lda pppNtpState
  ldx #(2 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeClientState

  networkClearFrom 3, NETWORK_VALUE_COLUMN
  ldx #$0000
@copyClock:
  lda clockDisplayText, x
  sta statusTileBuffer + (3 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN, x
  inx
  cpx #(TERMINAL_COLUMNS - NETWORK_VALUE_COLUMN)
  bne @copyClock

  networkClearFrom 4, NETWORK_VALUE_COLUMN
  lda pppNtpLastError
  ldx #(4 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeNtpError

  networkClearFrom 6, NETWORK_LONG_VALUE_COLUMN
  lda pppNtpVersion
  ldx #(6 * TERMINAL_COLUMNS) + NETWORK_LONG_VALUE_COLUMN
  jsr @writeDecimal8

  networkClearFrom 7, NETWORK_LONG_VALUE_COLUMN
  lda pppNtpStratum
  ldx #(7 * TERMINAL_COLUMNS) + NETWORK_LONG_VALUE_COLUMN
  jsr @writeDecimal8

  networkClearFrom 8, NETWORK_VALUE_COLUMN
  ldx #(8 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  ldy #$0000
@copyReference:
  lda pppNtpReferenceId, y
  cmp #$20
  bcc @referenceDot
  cmp #$7f
  bcc @referenceStore
@referenceDot:
  lda #'.'
@referenceStore:
  sta statusTileBuffer, x
  inx
  iny
  cpy #$0004
  bne @copyReference

  networkClearFrom 10, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppNtpRequestCount)
  ldx #(10 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 11, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppNtpResponseCount)
  ldx #(11 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 12, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppNtpTimeoutCount)
  ldx #(12 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  rtl

@dns:
  networkClearFrom 2, NETWORK_VALUE_COLUMN
  lda pppDnsState
  ldx #(2 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeClientState

  networkClearFrom 3, NETWORK_VALUE_COLUMN
  ldx #(3 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  ldy #$0000
  lda pppDnsQueryNameLength
  cmp #26
  bcc @hostLengthReady
  lda #25
@hostLengthReady:
  sta statusFormatValue
  stz statusFormatValue + 1
@copyHost:
  cpy statusFormatValue
  beq @hostCopied
  lda pppDnsQueryName, y
  sta statusTileBuffer, x
  inx
  iny
  bra @copyHost
@hostCopied:
  lda pppDnsQueryNameLength
  cmp #26
  bcc @hostDone
  dex
  lda #'>'
  sta statusTileBuffer, x
@hostDone:

  networkClearFrom 4, NETWORK_LONG_VALUE_COLUMN
  ldy #.loword(pppDnsResolver)
  ldx #(4 * TERMINAL_COLUMNS) + NETWORK_LONG_VALUE_COLUMN
  jsr @writeIpv4

  networkClearFrom 5, NETWORK_VALUE_COLUMN
  lda pppDnsFlags
  and #PPP_DNS_FLAG_RESPONSE_VALID
  beq @dnsAddressUnavailable
  ldy #.loword(pppDnsAnswerAddress)
  ldx #(5 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeIpv4
  bra @dnsAddressDone
@dnsAddressUnavailable:
  networkWriteImmediate 5, NETWORK_VALUE_COLUMN, "---.---.---.---"
@dnsAddressDone:

  networkClearFrom 6, NETWORK_LONG_VALUE_COLUMN
  rep #$20
  .a16
  lda pppDnsAnswerCount
  ldx #(6 * TERMINAL_COLUMNS) + NETWORK_LONG_VALUE_COLUMN
  jsr @writeDecimal16
  sep #$20
  .a8

  networkClearFrom 7, NETWORK_VALUE_COLUMN
  rep #$20
  .a16
  lda pppDnsTransactionId
  ldx #(7 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeHex16
  sep #$20
  .a8

  networkClearFrom 8, NETWORK_VALUE_COLUMN
  rep #$20
  .a16
  lda pppDnsRttFrames
  ldx #(8 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeDecimal16
  sep #$20
  .a8
  networkWriteAtX " FRAMES"

  networkClearFrom 9, NETWORK_VALUE_COLUMN
  lda pppDnsLastError
  ldx #(9 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeDnsError

  networkClearFrom 11, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppDnsQueryCount)
  ldx #(11 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 12, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppDnsResponseCount)
  ldx #(12 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 13, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppDnsDropCount)
  ldx #(13 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 14, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppDnsTimeoutCount)
  ldx #(14 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  rtl

@icmp:
  networkClearFrom 3, NETWORK_VALUE_COLUMN
  lda pppIcmpRequestState
  ldx #(3 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeClientState

  networkClearFrom 4, NETWORK_VALUE_COLUMN
  ldy #.loword(pppIcmpRequestDestination)
  ldx #(4 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeIpv4

  networkClearFrom 5, NETWORK_VALUE_COLUMN
  rep #$20
  .a16
  lda pppIcmpRequestIdentifier
  ldx #(5 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeHex16
  sep #$20
  .a8
  networkClearFrom 6, NETWORK_VALUE_COLUMN
  rep #$20
  .a16
  lda pppIcmpRequestSequence
  ldx #(6 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeDecimal16
  sep #$20
  .a8
  networkClearFrom 7, NETWORK_VALUE_COLUMN
  rep #$20
  .a16
  lda pppIcmpRequestRttFrames
  ldx #(7 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeDecimal16
  sep #$20
  .a8
  networkWriteAtX " FRAMES"
  networkClearFrom 8, NETWORK_VALUE_COLUMN
  lda pppIcmpRequestLastError
  ldx #(8 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeIcmpRequestError

  networkClearFrom 10, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppIcmpRequestCount)
  ldx #(10 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 11, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppIcmpRequestResponseCount)
  ldx #(11 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 12, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppIcmpRequestDropCount)
  ldx #(12 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 13, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppIcmpRequestTimeoutCount)
  ldx #(13 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32

  networkClearFrom 16, NETWORK_VALUE_COLUMN
  lda pppIcmpInboundState
  ldx #(16 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeClientState
  lda pppIcmpInboundFlags
  and #PPP_ICMP_INBOUND_FLAG_VALID
  beq :+
  jmp @inboundValid
:

  networkClearFrom 17, NETWORK_VALUE_COLUMN
  networkWriteImmediate 17, NETWORK_VALUE_COLUMN, "---.---.---.---"
  networkClearFrom 18, NETWORK_VALUE_COLUMN
  networkWriteImmediate 18, NETWORK_VALUE_COLUMN, "----"
  networkClearFrom 19, NETWORK_VALUE_COLUMN
  networkWriteImmediate 19, NETWORK_VALUE_COLUMN, "----"
  networkClearFrom 20, NETWORK_VALUE_COLUMN
  networkWriteImmediate 20, NETWORK_VALUE_COLUMN, "---"
  bra @inboundSnapshotDone

@inboundValid:
  networkClearFrom 17, NETWORK_VALUE_COLUMN
  ldy #.loword(pppIcmpInboundSource)
  ldx #(17 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeIpv4
  networkClearFrom 18, NETWORK_VALUE_COLUMN
  rep #$20
  .a16
  lda pppIcmpInboundIdentifier
  ldx #(18 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeHex16
  sep #$20
  .a8
  networkClearFrom 19, NETWORK_VALUE_COLUMN
  rep #$20
  .a16
  lda pppIcmpInboundSequence
  ldx #(19 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeDecimal16
  sep #$20
  .a8
  networkClearFrom 20, NETWORK_VALUE_COLUMN
  rep #$20
  .a16
  lda pppIcmpInboundPayloadLength
  ldx #(20 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeDecimal16
  sep #$20
  .a8
@inboundSnapshotDone:

  networkClearFrom 21, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppIcmpEchoRequestCount)
  ldx #(21 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 22, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppIcmpInboundReplyCount)
  ldx #(22 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 23, NETWORK_COUNTER_COLUMN
  ldy #.loword(pppIcmpInboundDropCount)
  ldx #(23 * TERMINAL_COLUMNS) + NETWORK_COUNTER_COLUMN
  jsr @writeCounter32
  networkClearFrom 24, NETWORK_VALUE_COLUMN
  lda pppIcmpInboundLastError
  ldx #(24 * TERMINAL_COLUMNS) + NETWORK_VALUE_COLUMN
  jsr @writeIcmpInboundError
  rtl

; Map the common five-state request lifecycle to the agreed vocabulary.
@writeClientState:
  cmp #$00
  networkJumpIfEqual @stateIdle
  cmp #$01
  networkJumpIfEqual @stateQueued
  cmp #$02
  networkJumpIfEqual @stateWaiting
  cmp #$03
  networkJumpIfEqual @stateReceived
  cmp #$04
  networkJumpIfEqual @stateFailed
  networkWriteAtX "UNKNOWN"
  rts
@stateIdle:
  networkWriteAtX "IDLE"
  rts
@stateQueued:
  networkWriteAtX "QUEUED"
  rts
@stateWaiting:
  networkWriteAtX "WAITING"
  rts
@stateReceived:
  networkWriteAtX "RECEIVED"
  rts
@stateFailed:
  networkWriteAtX "FAILED"
  rts

@writeNtpError:
  sta statusFormatValue
  cmp #$00
  bne :+
  networkWriteAtX "NONE"
  rts
:
  cmp #PPP_NTP_ERROR_LINK_NOT_OPEN
  networkJumpIfEqual @errorLink
  cmp #PPP_NTP_ERROR_TRANSMIT_FAILED
  networkJumpIfEqual @errorTransmit
  cmp #PPP_NTP_ERROR_WRONG_PORT
  networkJumpIfEqual @errorPort
  cmp #PPP_NTP_ERROR_TRUNCATED
  networkJumpIfEqual @errorTruncated
  cmp #PPP_NTP_ERROR_UNSUPPORTED_VERSION
  networkJumpIfEqual @errorVersion
  cmp #PPP_NTP_ERROR_UNEXPECTED_MODE
  networkJumpIfEqual @errorMode
  cmp #PPP_NTP_ERROR_KISS_OF_DEATH
  networkJumpIfEqual @errorKod
  cmp #PPP_NTP_ERROR_INVALID_STRATUM
  networkJumpIfEqual @errorStratum
  cmp #PPP_NTP_ERROR_UNSYNCHRONIZED
  networkJumpIfEqual @errorUnsync
  cmp #PPP_NTP_ERROR_ORIGINATE_MISMATCH
  networkJumpIfEqual @errorOriginate
  cmp #PPP_NTP_ERROR_PRE_UNIX_EPOCH
  networkJumpIfEqual @errorEpoch
  cmp #PPP_NTP_ERROR_TIMEOUT
  networkJumpIfEqual @errorTimeout
  cmp #PPP_NTP_ERROR_SOURCE_MISMATCH
  networkJumpIfEqual @errorSource
  cmp #PPP_NTP_ERROR_UNEXPECTED_RESPONSE
  networkJumpIfEqual @errorResponse
  cmp #PPP_NTP_ERROR_REQUEST_BUSY
  networkJumpIfEqual @errorBusy
  jmp @errorUnknown

@writeDnsError:
  sta statusFormatValue
  cmp #$00
  bne :+
  networkWriteAtX "NONE"
  rts
:
  cmp #PPP_DNS_ERROR_LINK_NOT_OPEN
  networkJumpIfEqual @errorLink
  cmp #PPP_DNS_ERROR_INVALID_NAME
  networkJumpIfEqual @errorName
  cmp #PPP_DNS_ERROR_REQUEST_BUSY
  networkJumpIfEqual @errorBusy
  cmp #PPP_DNS_ERROR_TRANSMIT_FAILED
  networkJumpIfEqual @errorTransmit
  cmp #PPP_DNS_ERROR_WRONG_PORT
  networkJumpIfEqual @errorPort
  cmp #PPP_DNS_ERROR_SOURCE_MISMATCH
  networkJumpIfEqual @errorSource
  cmp #PPP_DNS_ERROR_TRUNCATED
  networkJumpIfEqual @errorTruncated
  cmp #PPP_DNS_ERROR_IDENTIFIER_MISMATCH
  networkJumpIfEqual @errorIdentifier
  cmp #PPP_DNS_ERROR_NOT_RESPONSE
  networkJumpIfEqual @errorNotResponse
  cmp #PPP_DNS_ERROR_UNSUPPORTED_OPCODE
  networkJumpIfEqual @errorOpcode
  cmp #PPP_DNS_ERROR_TRUNCATED_RESPONSE
  networkJumpIfEqual @errorTruncatedResponse
  cmp #PPP_DNS_ERROR_RESPONSE_CODE
  networkJumpIfEqual @errorResponseCode
  cmp #PPP_DNS_ERROR_NO_QUESTION
  networkJumpIfEqual @errorNoQuestion
  cmp #PPP_DNS_ERROR_NO_ANSWER
  networkJumpIfEqual @errorNoAnswer
  cmp #PPP_DNS_ERROR_MALFORMED_NAME
  networkJumpIfEqual @errorMalformed
  cmp #PPP_DNS_ERROR_NO_IPV4_ANSWER
  networkJumpIfEqual @errorNoIpv4
  cmp #PPP_DNS_ERROR_TIMEOUT
  networkJumpIfEqual @errorTimeout
  jmp @errorUnknown

@writeIcmpRequestError:
  sta statusFormatValue
  cmp #$00
  bne :+
  networkWriteAtX "NONE"
  rts
:
  cmp #PPP_ICMP_REQUEST_ERROR_LINK_NOT_OPEN
  networkJumpIfEqual @errorLink
  cmp #PPP_ICMP_REQUEST_ERROR_REQUEST_BUSY
  networkJumpIfEqual @errorBusy
  cmp #PPP_ICMP_REQUEST_ERROR_TRANSMIT_FAILED
  networkJumpIfEqual @errorTransmit
  cmp #PPP_ICMP_REQUEST_ERROR_SOURCE_MISMATCH
  networkJumpIfEqual @errorSource
  cmp #PPP_ICMP_REQUEST_ERROR_IDENTIFIER_MISMATCH
  networkJumpIfEqual @errorIdentifier
  cmp #PPP_ICMP_REQUEST_ERROR_SEQUENCE_MISMATCH
  networkJumpIfEqual @errorSequence
  cmp #PPP_ICMP_REQUEST_ERROR_PAYLOAD_MISMATCH
  networkJumpIfEqual @errorPayload
  cmp #PPP_ICMP_REQUEST_ERROR_TIMEOUT
  networkJumpIfEqual @errorTimeout
  jmp @errorUnknown

@writeIcmpInboundError:
  sta statusFormatValue
  cmp #$00
  bne :+
  networkWriteAtX "NONE"
  rts
:
  cmp #PPP_ICMP_ERROR_TRUNCATED
  networkJumpIfEqual @errorTruncated
  cmp #PPP_ICMP_ERROR_UNSUPPORTED_TYPE
  networkJumpIfEqual @errorType
  cmp #PPP_ICMP_ERROR_NONZERO_CODE
  networkJumpIfEqual @errorCode
  cmp #PPP_ICMP_ERROR_INVALID_CHECKSUM
  networkJumpIfEqual @errorChecksum
  cmp #PPP_ICMP_ERROR_TRANSMIT_FAILED
  networkJumpIfEqual @errorTransmit
  cmp #PPP_ICMP_ERROR_PENDING_ABORTED
  networkJumpIfEqual @errorAborted
  jmp @errorUnknown

@errorNone:
  networkWriteAtX "NONE"
  rts
@errorLink:
  networkWriteAtX "LINK_NOT_OPEN"
  jmp @appendErrorCode
@errorTransmit:
  networkWriteAtX "TX_FAILED"
  jmp @appendErrorCode
@errorPort:
  networkWriteAtX "WRONG_PORT"
  jmp @appendErrorCode
@errorTruncated:
  networkWriteAtX "TRUNCATED"
  jmp @appendErrorCode
@errorVersion:
  networkWriteAtX "BAD_VERSION"
  jmp @appendErrorCode
@errorMode:
  networkWriteAtX "BAD_MODE"
  jmp @appendErrorCode
@errorKod:
  networkWriteAtX "KISS_OF_DEATH"
  jmp @appendErrorCode
@errorStratum:
  networkWriteAtX "BAD_STRATUM"
  jmp @appendErrorCode
@errorUnsync:
  networkWriteAtX "UNSYNCHRONIZED"
  jmp @appendErrorCode
@errorOriginate:
  networkWriteAtX "ORIGIN_MISMATCH"
  jmp @appendErrorCode
@errorEpoch:
  networkWriteAtX "PRE_UNIX_EPOCH"
  jmp @appendErrorCode
@errorTimeout:
  networkWriteAtX "TIMEOUT"
  jmp @appendErrorCode
@errorSource:
  networkWriteAtX "SOURCE_MISMATCH"
  jmp @appendErrorCode
@errorResponse:
  networkWriteAtX "UNEXPECTED_RESP"
  jmp @appendErrorCode
@errorBusy:
  networkWriteAtX "REQUEST_BUSY"
  jmp @appendErrorCode
@errorName:
  networkWriteAtX "INVALID_NAME"
  jmp @appendErrorCode
@errorIdentifier:
  networkWriteAtX "ID_MISMATCH"
  jmp @appendErrorCode
@errorNotResponse:
  networkWriteAtX "NOT_RESPONSE"
  jmp @appendErrorCode
@errorOpcode:
  networkWriteAtX "BAD_OPCODE"
  jmp @appendErrorCode
@errorTruncatedResponse:
  networkWriteAtX "TRUNCATED_RESP"
  jmp @appendErrorCode
@errorResponseCode:
  networkWriteAtX "RESPONSE_CODE"
  jmp @appendErrorCode
@errorNoQuestion:
  networkWriteAtX "NO_QUESTION"
  jmp @appendErrorCode
@errorNoAnswer:
  networkWriteAtX "NO_ANSWER"
  jmp @appendErrorCode
@errorMalformed:
  networkWriteAtX "MALFORMED_NAME"
  jmp @appendErrorCode
@errorNoIpv4:
  networkWriteAtX "NO_IPV4_ANSWER"
  jmp @appendErrorCode
@errorSequence:
  networkWriteAtX "SEQ_MISMATCH"
  jmp @appendErrorCode
@errorPayload:
  networkWriteAtX "PAYLOAD_MISMATCH"
  jmp @appendErrorCode
@errorType:
  networkWriteAtX "UNSUPPORTED_TYPE"
  jmp @appendErrorCode
@errorCode:
  networkWriteAtX "NONZERO_CODE"
  jmp @appendErrorCode
@errorChecksum:
  networkWriteAtX "BAD_CHECKSUM"
  jmp @appendErrorCode
@errorAborted:
  networkWriteAtX "PENDING_ABORTED"
  jmp @appendErrorCode
@errorUnknown:
  networkWriteAtX "UNKNOWN"
@appendErrorCode:
  networkWriteAtX " ("
  lda statusFormatValue
  jsr @writeHex8
  lda #')'
  sta statusTileBuffer, x
  inx
  rts

; Four network-order bytes at WRAM Y.
@writeIpv4:
  lda $0000, y
  jsr @writeDecimal8
  lda #'.'
  sta statusTileBuffer, x
  inx
  iny
  lda $0000, y
  jsr @writeDecimal8
  lda #'.'
  sta statusTileBuffer, x
  inx
  iny
  lda $0000, y
  jsr @writeDecimal8
  lda #'.'
  sta statusTileBuffer, x
  inx
  iny
  lda $0000, y
  jsr @writeDecimal8
  rts

@writeDecimal8:
  phy
  cmp #200
  bcc @decimalLessThan200
  sec
  sbc #200
  pha
  lda #'2'
  sta statusTileBuffer, x
  inx
  pla
  bra @decimalRequiredTens
@decimalLessThan200:
  cmp #100
  bcc @decimalOptionalTens
  sec
  sbc #100
  pha
  lda #'1'
  sta statusTileBuffer, x
  inx
  pla
@decimalRequiredTens:
  ldy #'0'
@decimalRequiredLoop:
  cmp #10
  bcc @decimalRequiredDone
  sec
  sbc #10
  iny
  bra @decimalRequiredLoop
@decimalRequiredDone:
  pha
  tya
  sta statusTileBuffer, x
  inx
  pla
  bra @decimalOnes
@decimalOptionalTens:
  cmp #10
  bcc @decimalOnes
  ldy #'0'
@decimalOptionalLoop:
  cmp #10
  bcc @decimalOptionalDone
  sec
  sbc #10
  iny
  bra @decimalOptionalLoop
@decimalOptionalDone:
  pha
  tya
  sta statusTileBuffer, x
  inx
  pla
@decimalOnes:
  clc
  adc #'0'
  sta statusTileBuffer, x
  inx
  ply
  rts

; A=16-bit unsigned value, X=destination.
@writeDecimal16:
  .a16
  sta statusFormatValue
  sep #$20
  .a8
  stz statusFormatStarted
  rep #$20
  .a16
  networkDecimalDigit 10000
  networkDecimalDigit 1000
  networkDecimalDigit 100
  networkDecimalDigit 10
  lda statusFormatValue
  sep #$20
  .a8
  clc
  adc #'0'
  sta statusTileBuffer, x
  inx
  rep #$20
  .a16
  rts

; Y points to a little-endian u32. Large counters stay honest without an
; expensive full 32-bit decimal conversion.
@writeCounter32:
  .a8
  lda $0002, y
  ora $0003, y
  beq @counterLow
  networkWriteAtX ">65535"
  rts
@counterLow:
  rep #$20
  .a16
  lda $0000, y
  jsr @writeDecimal16
  sep #$20
  .a8
  rts

@writeHex16:
  .a16
  sta statusFormatValue
  sep #$20
  .a8
  lda #'$'
  sta statusTileBuffer, x
  inx
  lda statusFormatValue + 1
  jsr @writeHex8
  lda statusFormatValue
  jsr @writeHex8
  rep #$20
  .a16
  rts

@writeHex8:
  .a8
  pha
  lsr
  lsr
  lsr
  lsr
  jsr @writeHexNibble
  pla
  and #$0f
@writeHexNibble:
  cmp #10
  bcc :+
  clc
  adc #('A' - 10)
  bra :++
:
  clc
  adc #'0'
:
  sta statusTileBuffer, x
  inx
  rts
.endproc
