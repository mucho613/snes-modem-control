.include "../macro/utility.asm"
.include "../ppp/constants.inc"
.include "constants.inc"

.code

.import modemDriverState, modemLastError, modemMailboxStage
.import modemAtStatus, modemSessionLastResult
.import modemMailboxHostSequence, modemMailboxProcessedSequence
.import modemMailboxObservedHost, modemMailboxObservedProcessed
.import modemMailboxCommand, modemMailboxStatus, modemMailboxResult
.import modemMailboxArguments, modemMailboxOutput
.import modemTransmitReadIndex, modemTransmitWriteIndex
.import modemInitialize
.import modemAtBegin
.import modemQueueByte, modemReadByte
.import modemClearTrace, modemFreezeTrace, modemResumeTrace
.import pppRunSelfTest
.import pppReceiveStart, pppReceiveStop
.import pppNtpRequest
.import pppIcmpRequestDestination, pppIcmpRequestBegin
.import pppDnsResolver, pppDnsQueryName, pppDnsQueryNameLength
.import pppDnsRequest

.export modemMailboxPoll
.proc modemMailboxPoll
  .a16
  .i16

  pha
  phb
  setDBR $7e

  mi8
  lda #$10
  sta modemMailboxStage

  lda modemMailboxStatus
  cmp #MODEM_MAILBOX_STATUS_RUNNING
  bne @checkNewCommand
  lda modemMailboxCommand
  cmp #MODEM_MAILBOX_COMMAND_QUICK_TEST
  beq @pollQuickTest
  cmp #MODEM_MAILBOX_COMMAND_AT_TRANSACTION
  beq @pollAtTransaction
  jmp @checkNewCommand

@pollQuickTest:
  lda modemDriverState
  cmp #MODEM_STATE_READY
  beq @quickPassed
  cmp #MODEM_STATE_ERROR
  beq @quickFailed
  jmp @done

@quickPassed:
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @done

@quickFailed:
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  lda #$01
  sta modemMailboxResult
  jmp @done

@pollAtTransaction:
  lda modemAtStatus
  cmp #MODEM_AT_STATUS_PASSED
  beq @atPassed
  cmp #MODEM_AT_STATUS_FAILED
  beq @atFailed
  jmp @done

@atPassed:
  lda modemSessionLastResult
  sta modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @done

@atFailed:
  lda modemLastError
  sta modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  jmp @done

@checkNewCommand:
  lda #$20
  sta modemMailboxStage
  m16
  lda modemMailboxProcessedSequence
  sta modemMailboxObservedProcessed
  lda modemMailboxHostSequence
  sta modemMailboxObservedHost
  cmp modemMailboxObservedProcessed
  bne @newCommand
  lda modemMailboxProcessedSequence + 2
  sta modemMailboxObservedProcessed + 2
  lda modemMailboxHostSequence + 2
  sta modemMailboxObservedHost + 2
  cmp modemMailboxObservedProcessed + 2
  bne @newCommand
  jmp @done16

@newCommand:
  mi8
  lda #$30
  sta modemMailboxStage
  lda #MODEM_MAILBOX_STATUS_RUNNING
  sta modemMailboxStatus
  stz modemMailboxResult
  stz modemMailboxResult + 1

  lda modemMailboxCommand
  cmp #MODEM_MAILBOX_COMMAND_INITIALIZE
  beq @initialize
  cmp #MODEM_MAILBOX_COMMAND_QUICK_TEST
  beq @quickTest
  cmp #MODEM_MAILBOX_COMMAND_CLEAR_TRACE
  bne :+
  jmp @clearTrace
:
  cmp #MODEM_MAILBOX_COMMAND_FREEZE_TRACE
  bne :+
  jmp @freezeTrace
:
  cmp #MODEM_MAILBOX_COMMAND_RESUME_TRACE
  bne :+
  jmp @resumeTrace
:
  cmp #MODEM_MAILBOX_COMMAND_AT_TRANSACTION
  beq @atTransaction
  cmp #MODEM_MAILBOX_COMMAND_BINARY_TRANSMIT
  beq @binaryTransmit
  cmp #MODEM_MAILBOX_COMMAND_BINARY_RECEIVE
  bne :+
  jmp @binaryReceive
:
  cmp #MODEM_MAILBOX_COMMAND_BINARY_STRESS_TRANSMIT
  bne :+
  jmp @binaryStressTransmit
:
  cmp #MODEM_MAILBOX_COMMAND_PPP_SELF_TEST
  bne :+
  jmp @pppSelfTest
:
  cmp #MODEM_MAILBOX_COMMAND_PPP_RECEIVE_START
  bne :+
  jmp @pppReceiveStart
:
  cmp #MODEM_MAILBOX_COMMAND_PPP_RECEIVE_STOP
  bne :+
  jmp @pppReceiveStop
:
  cmp #MODEM_MAILBOX_COMMAND_NTP_REQUEST
  bne :+
  jmp @ntpRequest
:
  cmp #MODEM_MAILBOX_COMMAND_ICMP_ECHO_REQUEST
  bne :+
  jmp @icmpEchoRequest
:
  cmp #MODEM_MAILBOX_COMMAND_DNS_QUERY
  bne :+
  jmp @dnsQuery
:
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  lda #$ff
  sta modemMailboxResult
  jmp @commitCommand

@initialize:
  mi16
  jsr modemInitialize
  mi8
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@quickTest:
  mi16
  jsr modemInitialize
  mi8
  ; Completion is reported when modemSessionPoll reaches READY or ERROR.
  jmp @commitCommand

@atTransaction:
  jsr modemAtBegin
  bcs :+
  jmp @commitCommand
:
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  lda modemLastError
  sta modemMailboxResult
  jmp @commitCommand

@binaryTransmit:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq :+
  jmp @binaryInvalid
:
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  beq :+
  jmp @binaryInvalid
:
  lda modemMailboxArguments + MODEM_BINARY_ARGUMENT_LENGTH
  bne :+
  jmp @binaryInvalid
:
  cmp #(MODEM_BINARY_CHUNK_MAX_LENGTH + 1)
  bcc :+
  jmp @binaryInvalid
:
  tay
  ldx #$00
@binaryTransmitLoop:
  lda modemMailboxArguments + MODEM_BINARY_ARGUMENT_DATA, x
  jsr modemQueueByte
  bcc :+
  jmp @binaryInvalid
:
  inx
  dey
  bne @binaryTransmitLoop
  stx modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@binaryReceive:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq @binaryReceiveStateValid
  cmp #MODEM_STATE_READY
  beq @binaryReceiveStateValid
  jmp @binaryInvalid
@binaryReceiveStateValid:
  ldx #$00
@binaryReceiveLoop:
  cpx #MODEM_BINARY_CHUNK_MAX_LENGTH
  beq @binaryReceiveDone
  jsr modemReadByte
  bcs @binaryReceiveDone
  sta modemMailboxOutput, x
  inx
  bra @binaryReceiveLoop
@binaryReceiveDone:
  stx modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@binaryStressTransmit:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq :+
  jmp @binaryInvalid
:
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  beq :+
  jmp @binaryInvalid
:
  ; Fill the 255-byte usable TX ring with 0x00..0xFE before modemPoll can
  ; consume it. This deliberately creates the largest possible controller-
  ; interface burst for backpressure and byte-acceptance diagnostics.
  ldx #$00
@binaryStressTransmitLoop:
  txa
  jsr modemQueueByte
  bcc :+
  jmp @binaryInvalid
:
  inx
  cpx #MODEM_RING_CAPACITY
  bne @binaryStressTransmitLoop
  stx modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@pppSelfTest:
  jsr pppRunSelfTest
  bcs @pppSelfTestFailed
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@pppSelfTestFailed:
  sta modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  jmp @commitCommand

@pppReceiveStart:
  jsr pppReceiveStart
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@pppReceiveStop:
  jsr pppReceiveStop
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@ntpRequest:
  i16
  jsr pppNtpRequest
  i8
  bcs @ntpRequestFailed
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@ntpRequestFailed:
  sta modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  jmp @commitCommand

@icmpEchoRequest:
  ldx #$00
@icmpEchoCopyDestination:
  lda modemMailboxArguments, x
  sta pppIcmpRequestDestination, x
  inx
  cpx #$04
  bne @icmpEchoCopyDestination
  i16
  jsr pppIcmpRequestBegin
  i8
  bcs @icmpEchoRequestFailed
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@icmpEchoRequestFailed:
  sta modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  jmp @commitCommand

@dnsQuery:
  lda modemMailboxArguments + 4
  beq @dnsQueryInvalid
  cmp #(PPP_DNS_MAXIMUM_NAME_LENGTH + 1)
  bcs @dnsQueryInvalid
  sta pppDnsQueryNameLength
  ldx #$00
@dnsCopyResolver:
  lda modemMailboxArguments, x
  sta pppDnsResolver, x
  inx
  cpx #$04
  bne @dnsCopyResolver
  ldx #$00
@dnsCopyName:
  lda modemMailboxArguments + 5, x
  sta pppDnsQueryName, x
  inx
  cpx pppDnsQueryNameLength
  bne @dnsCopyName
  i16
  jsr pppDnsRequest
  i8
  bcs @dnsQueryFailed
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@dnsQueryInvalid:
  lda #PPP_DNS_ERROR_INVALID_NAME
@dnsQueryFailed:
  sta modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  jmp @commitCommand

@binaryInvalid:
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  lda #MODEM_ERROR_AT_INVALID
  sta modemMailboxResult
  jmp @commitCommand

@clearTrace:
  jsr modemClearTrace
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@freezeTrace:
  jsr modemFreezeTrace
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@resumeTrace:
  jsr modemResumeTrace
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus

@commitCommand:
  lda #$40
  sta modemMailboxStage
  m16
  lda modemMailboxHostSequence
  sta modemMailboxProcessedSequence
  lda modemMailboxHostSequence + 2
  sta modemMailboxProcessedSequence + 2

@done16:
  mi8
@done:
  lda #$90
  sta modemMailboxStage
  mi16
  plb
  pla
  rts
.endproc
