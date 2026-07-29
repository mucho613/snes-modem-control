.include "../macro/utility.asm"
.include "constants.inc"

.code

.import modemDriverState
.import modemMailboxHostSequence, modemMailboxProcessedSequence
.import modemMailboxCommand, modemMailboxStatus, modemMailboxResult
.import modemInitialize
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

  lda modemMailboxStatus
  cmp #MODEM_MAILBOX_STATUS_RUNNING
  bne @checkNewCommand
  lda modemMailboxCommand
  cmp #MODEM_MAILBOX_COMMAND_QUICK_TEST
  bne @checkNewCommand
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

@checkNewCommand:
  rep #$20
  .a16
  lda modemMailboxHostSequence
  cmp modemMailboxProcessedSequence
  bne @newCommand
  lda modemMailboxHostSequence + 2
  cmp modemMailboxProcessedSequence + 2
  beq @done16

@newCommand:
  sep #$30
  .a8
  .i8
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
  beq @clearTrace
  cmp #MODEM_MAILBOX_COMMAND_FREEZE_TRACE
  beq @freezeTrace
  cmp #MODEM_MAILBOX_COMMAND_RESUME_TRACE
  beq @resumeTrace
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  lda #$ff
  sta modemMailboxResult
  bra @commitCommand

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
  bra @commitCommand

@quickTest:
  rep #$30
  .a16
  .i16
  jsr modemInitialize
  sep #$30
  .a8
  .i8
  ; Completion is reported when modemSessionPoll reaches READY or ERROR.
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
  rep #$30
  .a16
  .i16
  plb
  pla
  rts
.endproc
