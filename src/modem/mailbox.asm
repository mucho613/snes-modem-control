.include "../macro/utility.asm"
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

.export modemMailboxPoll
.proc modemMailboxPoll
  .a16
  .i16

  pha
  phb
  setDBR $7e

  sep #$30
  .a8
  .i8
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
  rep #$20
  .a16
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
  sep #$30
  .a8
  .i8
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
  beq @binaryReceive
  cmp #MODEM_MAILBOX_COMMAND_BINARY_STRESS_TRANSMIT
  bne :+
  jmp @binaryStressTransmit
:
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  lda #$ff
  sta modemMailboxResult
  jmp @commitCommand

@initialize:
  rep #$30
  .a16
  .i16
  jsr modemInitialize
  sep #$30
  .a8
  .i8
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  jmp @commitCommand

@quickTest:
  rep #$30
  .a16
  .i16
  jsr modemInitialize
  sep #$30
  .a8
  .i8
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
  bne @binaryInvalid
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  bne @binaryInvalid
  lda modemMailboxArguments + MODEM_BINARY_ARGUMENT_LENGTH
  beq @binaryInvalid
  cmp #(MODEM_BINARY_CHUNK_MAX_LENGTH + 1)
  bcs @binaryInvalid
  tay
  ldx #$00
@binaryTransmitLoop:
  lda modemMailboxArguments + MODEM_BINARY_ARGUMENT_DATA, x
  jsr modemQueueByte
  bcs @binaryInvalid
  inx
  dey
  bne @binaryTransmitLoop
  stx modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  bra @commitCommand

@binaryReceive:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq @binaryReceiveStateValid
  cmp #MODEM_STATE_READY
  bne @binaryInvalid
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
  bra @commitCommand

@binaryStressTransmit:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  bne @binaryInvalid
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  bne @binaryInvalid
  ; Fill the 255-byte usable TX ring with 0x00..0xFE before modemPoll can
  ; consume it. This deliberately creates the largest possible controller-
  ; interface burst for backpressure and byte-acceptance diagnostics.
  ldx #$00
@binaryStressTransmitLoop:
  txa
  jsr modemQueueByte
  bcs @binaryInvalid
  inx
  cpx #MODEM_RING_CAPACITY
  bne @binaryStressTransmitLoop
  stx modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  bra @commitCommand

@binaryInvalid:
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  lda #MODEM_ERROR_AT_INVALID
  sta modemMailboxResult
  bra @commitCommand

@clearTrace:
  jsr modemClearTrace
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  bra @commitCommand

@freezeTrace:
  jsr modemFreezeTrace
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  bra @commitCommand

@resumeTrace:
  jsr modemResumeTrace
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus

@commitCommand:
  lda #$40
  sta modemMailboxStage
  rep #$20
  .a16
  lda modemMailboxHostSequence
  sta modemMailboxProcessedSequence
  lda modemMailboxHostSequence + 2
  sta modemMailboxProcessedSequence + 2

@done16:
  sep #$30
  .a8
  .i8

@done:
  lda #$90
  sta modemMailboxStage
  rep #$30
  .a16
  .i16
  plb
  pla
  rts
.endproc
