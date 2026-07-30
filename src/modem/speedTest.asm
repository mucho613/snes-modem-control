.include "constants.inc"
.include "../macro/utility.asm"

.segment "BANK1_CODE"

.import frameCounter
.import modemDriverState
.import modemTransmitReadIndex, modemTransmitWriteIndex
.import modemMailboxStatus, modemMailboxResult
.import modemMailboxArguments, modemMailboxOutput
.import modemSpeedTestMode, modemSpeedTestRemaining, modemSpeedTestProcessed
.import modemSpeedTestLfsr, modemSpeedTestMismatchCount
.import modemSpeedTestFirstMismatch, modemSpeedTestExpected, modemSpeedTestActual
.import modemSpeedTestStartFrame, modemSpeedTestEndFrame
.import modemQueueByte, modemReadByte

.export modemSpeedTestInitialize
.export modemSpeedTestBeginTransmit, modemSpeedTestBeginReceive
.export modemSpeedTestPoll

.proc modemSpeedTestInitialize
  .a8
  .i8

  phb
  setDBR $7e
  stz modemSpeedTestMode
  plb
  rtl
.endproc

.proc modemSpeedTestBeginTransmit
  .a8
  .i8

  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  bne @invalid
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  bne @invalid
  lda #MODEM_SPEED_TEST_TRANSMIT
  bra modemSpeedTestBegin
@invalid:
  sec
  rtl
.endproc

.proc modemSpeedTestBeginReceive
  .a8
  .i8

  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  bne @invalid
  lda #MODEM_SPEED_TEST_RECEIVE
  bra modemSpeedTestBegin
@invalid:
  sec
  rtl
.endproc

; Input A is the requested speed-test mode.
.proc modemSpeedTestBegin
  .a8
  .i8

  pha
  lda modemMailboxArguments + MODEM_PRBS_ARGUMENT_LENGTH
  ora modemMailboxArguments + MODEM_PRBS_ARGUMENT_LENGTH + 1
  ora modemMailboxArguments + MODEM_PRBS_ARGUMENT_LENGTH + 2
  ora modemMailboxArguments + MODEM_PRBS_ARGUMENT_LENGTH + 3
  beq @invalid
  lda modemMailboxArguments + MODEM_PRBS_ARGUMENT_SEED
  ora modemMailboxArguments + MODEM_PRBS_ARGUMENT_SEED + 1
  beq @invalid

  m16
  lda modemMailboxArguments + MODEM_PRBS_ARGUMENT_LENGTH
  sta modemSpeedTestRemaining
  lda modemMailboxArguments + MODEM_PRBS_ARGUMENT_LENGTH + 2
  sta modemSpeedTestRemaining + 2
  lda modemMailboxArguments + MODEM_PRBS_ARGUMENT_SEED
  sta modemSpeedTestLfsr
  stz modemSpeedTestProcessed
  stz modemSpeedTestProcessed + 2
  stz modemSpeedTestMismatchCount
  stz modemSpeedTestMismatchCount + 2
  lda #$ffff
  sta modemSpeedTestFirstMismatch
  sta modemSpeedTestFirstMismatch + 2
  lda frameCounter
  sta modemSpeedTestStartFrame
  lda frameCounter + 2
  sta modemSpeedTestStartFrame + 2
  m8
  stz modemSpeedTestExpected
  stz modemSpeedTestActual
  pla
  sta modemSpeedTestMode
  clc
  rtl

@invalid:
  pla
  sec
  rtl
.endproc

.proc modemSpeedTestPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e
  mi8

  lda modemSpeedTestMode
  beq @done
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq :+
  lda #MODEM_ERROR_AT_INVALID
  sta modemMailboxResult
  lda #MODEM_MAILBOX_STATUS_FAILED
  sta modemMailboxStatus
  stz modemSpeedTestMode
  bra @done
:
  lda modemSpeedTestMode
  cmp #MODEM_SPEED_TEST_TRANSMIT
  beq @transmit
  cmp #MODEM_SPEED_TEST_RECEIVE
  beq @receive
  stz modemSpeedTestMode
  bra @done

@transmit:
  jsr modemSpeedTestHasRemaining
  bcc @transmitDrain
  lda modemSpeedTestLfsr
  jsr modemQueueByte
  bcs @done
  jsr modemSpeedTestAdvance
  bra @transmit

@transmitDrain:
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  bne @done
  jsr modemSpeedTestFinish
  bra @done

@receive:
  jsr modemSpeedTestHasRemaining
  bcc @receiveComplete
  jsr modemReadByte
  bcs @done
  sta modemSpeedTestActual
  lda modemSpeedTestLfsr
  sta modemSpeedTestExpected
  cmp modemSpeedTestActual
  beq :+
  jsr modemSpeedTestRecordMismatch
:
  jsr modemSpeedTestAdvance
  bra @receive

@receiveComplete:
  jsr modemSpeedTestFinish

@done:
  mi16
  ply
  plx
  plb
  pla
  rtl
.endproc

; Carry set when at least one requested byte remains.
.proc modemSpeedTestHasRemaining
  .a8
  .i8

  lda modemSpeedTestRemaining
  ora modemSpeedTestRemaining + 1
  ora modemSpeedTestRemaining + 2
  ora modemSpeedTestRemaining + 3
  beq @empty
  sec
  rts
@empty:
  clc
  rts
.endproc

.proc modemSpeedTestAdvance
  .a8
  .i8

  m16
  lda modemSpeedTestLfsr
  lsr
  bcc :+
  eor #$b400
:
  sta modemSpeedTestLfsr

  inc modemSpeedTestProcessed
  bne :+
  inc modemSpeedTestProcessed + 2
:
  lda modemSpeedTestRemaining
  bne :+
  dec modemSpeedTestRemaining + 2
:
  dec modemSpeedTestRemaining
  m8
  rts
.endproc

.proc modemSpeedTestRecordMismatch
  .a8
  .i8

  lda modemSpeedTestMismatchCount
  ora modemSpeedTestMismatchCount + 1
  ora modemSpeedTestMismatchCount + 2
  ora modemSpeedTestMismatchCount + 3
  bne :+
  m16
  lda modemSpeedTestProcessed
  sta modemSpeedTestFirstMismatch
  lda modemSpeedTestProcessed + 2
  sta modemSpeedTestFirstMismatch + 2
  m8
:
  modemIncrement32 modemSpeedTestMismatchCount
  rts
.endproc

.proc modemSpeedTestFinish
  .a8
  .i8

  m16
  lda frameCounter
  sta modemSpeedTestEndFrame
  lda frameCounter + 2
  sta modemSpeedTestEndFrame + 2

  lda modemSpeedTestProcessed
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_PROCESSED
  lda modemSpeedTestProcessed + 2
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_PROCESSED + 2
  lda modemSpeedTestMismatchCount
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_MISMATCH_COUNT
  sta modemMailboxResult
  lda modemSpeedTestMismatchCount + 2
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_MISMATCH_COUNT + 2
  lda modemSpeedTestFirstMismatch
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_FIRST_MISMATCH
  lda modemSpeedTestFirstMismatch + 2
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_FIRST_MISMATCH + 2
  lda modemSpeedTestStartFrame
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_START_FRAME
  lda modemSpeedTestStartFrame + 2
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_START_FRAME + 2
  lda modemSpeedTestEndFrame
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_END_FRAME
  lda modemSpeedTestEndFrame + 2
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_END_FRAME + 2
  m8
  lda modemSpeedTestExpected
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_EXPECTED
  lda modemSpeedTestActual
  sta modemMailboxOutput + MODEM_PRBS_OUTPUT_ACTUAL
  lda #MODEM_MAILBOX_STATUS_PASSED
  sta modemMailboxStatus
  stz modemSpeedTestMode
  rts
.endproc
