.include "../registers.inc"
.include "constants.inc"
.include "nop.inc"

.code

.import modemLastDataReport, modemLastStatusReport
.import modemLastDiscardReason, modemTransferHadTransmit
.import modemPeekTransmitByte, modemConsumeTransmitByte
.import modemStoreReceivedByte, modemRecordDiscard
.import modemRecordTrace

.export modemTransfer9
.proc modemTransfer9
  .a8
  .i8

  stz modemLastDataReport
  stz modemLastDataReport + 1
  stz modemLastStatusReport
  stz modemLastStatusReport + 1
  stz modemTransferHadTransmit

  stz .lobyte(JOYOUT)
  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)

  ; The first output bit says whether a transmit byte follows.
  jsr modemPeekTransmitByte
  bcs @noTransmitStartBit
  lda #$01
  sta modemTransferHadTransmit
  lda #MODEM_TX_ASSERT
  bra @writeStartBit

@noTransmitStartBit:
  lda #MODEM_TX_RELEASE

@writeStartBit:
  sta .lobyte(WRIO)
  nop8Times
  nop8Times

  lda .lobyte(JOYSER1)
  lsr
  rol modemLastDataReport
  lsr
  rol modemLastStatusReport

  jsr modemPeekTransmitByte
  bcc @transmitByteLoaded
  lda #$ff

@transmitByteLoaded:
  ldy #$08
@bitLoop:
  asl
  xba
  lda #MODEM_TX_RELEASE
  bcs @writeTransmitBit
  lda #MODEM_TX_ASSERT

@writeTransmitBit:
  sta .lobyte(WRIO)
  nop8Times

  lda .lobyte(JOYSER1)
  lsr
  rol modemLastDataReport
  rol modemLastDataReport + 1
  lsr
  rol modemLastStatusReport
  rol modemLastStatusReport + 1
  xba
  dey
  bne @bitLoop

  lda #MODEM_TX_RELEASE
  sta .lobyte(WRIO)

  ; Align the first sampled bit with the same 16-bit representation used by a
  ; complete report: flag in Data1 low byte, value in Data1 high byte.
  ldy #$07
@alignReports:
  clc
  rol modemLastDataReport
  rol modemLastDataReport + 1
  clc
  rol modemLastStatusReport
  rol modemLastStatusReport + 1
  dey
  bne @alignReports

  lda modemTransferHadTransmit
  beq @receiveDecision
  jsr modemConsumeTransmitByte
  lda #MODEM_TRACE_TX
  jsr modemRecordTrace

@receiveDecision:
  lda modemLastStatusReport + 1
  bit #MODEM_STATUS_READY_MASK
  bne @statusReady

  lda #MODEM_DISCARD_STATUS_NOT_READY
  sta modemLastDiscardReason
  lda modemLastDataReport
  bit #MODEM_RX_PRESENT_MASK
  beq @recordTransfer
  lda #MODEM_DISCARD_STATUS_NOT_READY
  jsr modemRecordDiscard
  lda #MODEM_TRACE_RX_DISCARDED
  jsr modemRecordTrace
  bra @recordTransfer

@statusReady:
  lda modemLastDataReport
  bit #MODEM_RX_PRESENT_MASK
  bne @receivePresent
  lda #MODEM_DISCARD_NO_DATA
  sta modemLastDiscardReason
  bra @recordTransfer

@receivePresent:
  lda #MODEM_DISCARD_NONE
  sta modemLastDiscardReason
  lda modemLastDataReport + 1
  jsr modemStoreReceivedByte
  bcs @receiveOverflow
  lda #MODEM_TRACE_RX_ACCEPTED
  jsr modemRecordTrace
  bra @recordTransfer

@receiveOverflow:
  lda #MODEM_TRACE_RX_DISCARDED
  jsr modemRecordTrace

@recordTransfer:
  lda #MODEM_TRACE_TRANSFER9
  jsr modemRecordTrace
  rts
.endproc
