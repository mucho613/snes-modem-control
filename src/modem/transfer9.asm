.include "../registers.inc"
.include "constants.inc"
.include "nop.inc"

.code

.import modemLastDataReport, modemLastStatusReport
.import modemLastDiscardReason, modemTransferHadTransmit
.import modemTransmitReadIndex, modemTransmitWriteIndex, modemTransmitBuffer
.import modemConsumeTransmitByte
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

  ; Match the transfer waveform used by the original working implementation.
  ; Bank $80 provides direct absolute access to the I/O registers and mirrors
  ; the first 8 KiB of WRAM, where the driver state and rings reside.
  phb
  pea $8000
  plb
  plb

  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)

  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  beq @noTransmitStartBit
  inc modemTransferHadTransmit
  stz WRIO

@noTransmitStartBit:
  nop8Times
  nop8Times

  lda .lobyte(JOYSER1)
  lsr
  rol modemLastDataReport
  lsr
  rol modemLastStatusReport

  lda modemTransferHadTransmit
  beq @transmitBufferEmpty
  ldy modemTransmitReadIndex
  lda modemTransmitBuffer, y
  bra @loadTransmitByteEnd

@transmitBufferEmpty:
  lda #MODEM_TX_RELEASE

@loadTransmitByteEnd:
  ldy #$08
@bitLoop:
  sta WRIO
  asl
  xba
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
  sta WRIO

  ; Align the 8 data bits and final transfer RX-present bit: asserted flag in
  ; Data1 low byte, value in Data1 high byte.
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

  plb

  lda modemTransferHadTransmit
  beq @receiveDecision
  ; The controller protocol has no identified per-byte TX acknowledgement.
  ; Consume after the complete waveform; this records delivery to the NDM24
  ; interface, not delivery across the telephone carrier.
  jsr modemConsumeTransmitByte
  lda #MODEM_TRACE_TX
  jsr modemRecordTrace

@receiveDecision:
  lda modemLastDataReport
  and #MODEM_RX_PRESENT_MASK
  cmp #MODEM_RX_PRESENT_ASSERTED
  beq @receivePresent
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
