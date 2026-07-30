.include "../macro/utility.asm"
.include "../modem/constants.inc"
.include "constants.inc"

.code

.import modemDriverState, modemSessionLastResult, modemSessionLineLength
.import modemSetState
.import modemReadByte
.import pppDecoderReset, pppDecoderPush, pppDecoderDiscardPartial
.import pppLastInvalidReason
.import pppSnapshotBegin, pppSnapshotEnd
.import pppReceiveEnabled, pppReceiveActive, pppFrameReady, pppReceiveLastEvent
.import pppReceiveLastInvalidReason, pppReceiveDrainRemaining
.import pppReceiveByteCount, pppReceiveFrameCount, pppReceiveFcsErrorCount
.import pppReceiveInvalidCount, pppReceiveOverflowCount
.import pppReceiveDrainBudgetYieldCount
.import pppCarrierLossCount, pppCarrierTailByteCount
.import pppCarrierLineIndex, pppCarrierScratchByte
.import pppCarrierTestSavedModemState, pppCarrierTestSavedSessionResult
.import pppCarrierTestSavedLineLength

.export pppReceiveInitialize, pppReceivePoll
.export pppReceiveStart, pppReceiveStop
.export pppReceivePushByte, pppReceivePushConnectedByte, pppReleaseFrame
.export pppCarrierLossRunSelfTest

; Initialize permanent receive diagnostics and decoder state at boot.
.proc pppReceiveInitialize
  .a8
  .i16

  phb
  setDBR $7e

  stz pppReceiveEnabled
  stz pppReceiveActive
  stz pppFrameReady
  stz pppReceiveLastEvent
  stz pppReceiveLastInvalidReason
  stz pppReceiveDrainRemaining
  stz pppReceiveByteCount
  stz pppReceiveByteCount + 1
  stz pppReceiveByteCount + 2
  stz pppReceiveByteCount + 3
  stz pppReceiveFrameCount
  stz pppReceiveFrameCount + 1
  stz pppReceiveFrameCount + 2
  stz pppReceiveFrameCount + 3
  stz pppReceiveFcsErrorCount
  stz pppReceiveFcsErrorCount + 1
  stz pppReceiveFcsErrorCount + 2
  stz pppReceiveFcsErrorCount + 3
  stz pppReceiveInvalidCount
  stz pppReceiveInvalidCount + 1
  stz pppReceiveInvalidCount + 2
  stz pppReceiveInvalidCount + 3
  stz pppReceiveOverflowCount
  stz pppReceiveOverflowCount + 1
  stz pppReceiveOverflowCount + 2
  stz pppReceiveOverflowCount + 3
  stz pppReceiveDrainBudgetYieldCount
  stz pppReceiveDrainBudgetYieldCount + 1
  stz pppReceiveDrainBudgetYieldCount + 2
  stz pppReceiveDrainBudgetYieldCount + 3
  stz pppCarrierLossCount
  stz pppCarrierLossCount + 1
  stz pppCarrierLossCount + 2
  stz pppCarrierLossCount + 3
  stz pppCarrierTailByteCount
  stz pppCarrierTailByteCount + 1
  stz pppCarrierTailByteCount + 2
  stz pppCarrierTailByteCount + 3
  stz pppCarrierLineIndex
  jsr pppDecoderReset

  plb
  rts
.endproc

; Drain CONNECTED raw bytes from the NDM24 RX ring into the RFC 1662 decoder.
; A completed frame stops the drain and remains stable until pppReleaseFrame.
.proc pppReceivePoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e

  mi8
  lda pppReceiveEnabled
  bne @checkConnected
  lda pppReceiveActive
  bne :+
  jmp done
:
  jsr pppSnapshotBegin
  stz pppReceiveActive
  jsr pppSnapshotEnd
  jmp done

@checkConnected:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq connected
  lda pppReceiveActive
  bne :+
  jmp done
:
  jsr pppSnapshotBegin
  stz pppReceiveActive
  jsr pppSnapshotEnd
  jmp done

connected:
  lda pppReceiveActive
  bne checkFrameOwnership
  jsr pppSnapshotBegin
  lda #$01
  sta pppReceiveActive
  stz pppFrameReady
  i16
  jsr pppDecoderReset
  i8
  jsr pppSnapshotEnd

checkFrameOwnership:
  lda pppFrameReady
  beq :+
  jmp done
:

  lda #PPP_RECEIVE_DRAIN_BUDGET
  sta pppReceiveDrainRemaining

drain:
  jsr modemReadByte
  bcs done
  i16
  jsr pppReceivePushConnectedByte
  i8
  cmp #PPP_EVENT_CARRIER_LOST
  beq carrierTail
  lda pppFrameReady
  bne done
  dec pppReceiveDrainRemaining
  bne drain
  jsr pppSnapshotBegin
  pppIncrement32 pppReceiveDrainBudgetYieldCount
  jsr pppSnapshotEnd
  bra done

carrierTail:
  ; NDM24 can emit the same NO CARRIER result twice for one peer-driven
  ; disconnect. The current modem poll may already have queued that second
  ; line. It belongs to the completed link, so consume the rest of this RX
  ; burst before exposing READY to the next AT transaction.
  jsr pppSnapshotBegin
carrierTailByte:
  jsr modemReadByte
  bcs carrierTailDone
  pppIncrement32 pppCarrierTailByteCount
  bra carrierTailByte
carrierTailDone:
  jsr pppSnapshotEnd

done:
  mi16
  ply
  plx
  plb
  pla
  rts
.endproc

; Feed one byte while PPP owns a connected NDM24 stream. Raw result lines are
; observed before RFC 1662 decoding. Because the local receive ACCM remains
; $FFFFFFFF during this phase, CR and LF inside a conforming PPP frame are
; escaped and cannot complete the unescaped "NO CARRIER" sentinel.
;
; Input A=raw byte, output A=PPP_EVENT_*. Preserves X, Y, DBR.
.proc pppReceivePushConnectedByte
  .a8
  .i16

  phb
  phy
  setDBR $7e
  sta pppCarrierScratchByte

  ldy pppCarrierLineIndex
  cpy #$0000
  bne @expect1
  cmp #'N'
  beq @advance
  jmp @restart

@advance:
  iny
  sty pppCarrierLineIndex
@decode:
  lda pppCarrierScratchByte
  jsr pppReceivePushByte
  ply
  plb
  rts

@expect1:
  cpy #$0001
  bne @expect2
  cmp #'O'
  beq @advance
  jmp @restart
@expect2:
  cpy #$0002
  bne @expect3
  cmp #' '
  beq @advance
  jmp @restart
@expect3:
  cpy #$0003
  bne @expect4
  cmp #'C'
  beq @advance
  jmp @restart
@expect4:
  cpy #$0004
  bne @expect5
  cmp #'A'
  beq @advance
  jmp @restart
@expect5:
  cpy #$0005
  bne @expect6
  cmp #'R'
  beq @advance
  jmp @restart
@expect6:
  cpy #$0006
  bne @expect7
  cmp #'R'
  beq @advance
  jmp @restart
@expect7:
  cpy #$0007
  bne @expect8
  cmp #'I'
  beq @advance
  jmp @restart
@expect8:
  cpy #$0008
  bne @expect9
  cmp #'E'
  beq @advance
  jmp @restart
@expect9:
  cpy #$0009
  bne @expect10
  cmp #'R'
  beq @advance
  jmp @restart
@expect10:
  cpy #$000a
  bne @expect11
  cmp #$0d
  bne :+
  jmp @advance
:
  jmp @restart
@expect11:
  cmp #$0a
  beq @carrierLost

@restart:
  lda pppCarrierScratchByte
  cmp #'N'
  bne @clearMatch
  lda #$01
  sta pppCarrierLineIndex
  jmp @decode
@clearMatch:
  stz pppCarrierLineIndex
  jmp @decode

@carrierLost:
  stz pppCarrierLineIndex
  jsr pppSnapshotBegin
  stz pppReceiveEnabled
  stz pppReceiveActive
  stz pppFrameReady
  pppIncrement32 pppCarrierLossCount
  jsr pppDecoderDiscardPartial
  lda #PPP_EVENT_CARRIER_LOST
  sta pppReceiveLastEvent
  jsr pppSnapshotEnd

  lda #MODEM_SESSION_RESULT_NO_CARRIER
  sta modemSessionLastResult
  stz modemSessionLineLength
  lda #MODEM_STATE_READY
  i8
  jsr modemSetState
  i16
  lda #PPP_EVENT_CARRIER_LOST
  ply
  plb
  rts
.endproc

; Explicit ownership switch. Raw binary tests retain the NDM24 RX ring while
; disabled; the future link state machine enables PPP after CONNECT.
.proc pppReceiveStart
  .a8
  .i8

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  lda #$01
  sta pppReceiveEnabled
  stz pppReceiveActive
  stz pppFrameReady
  jsr pppSnapshotEnd
  plb
  rts
.endproc

.proc pppReceiveStop
  .a8
  .i8

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  stz pppReceiveEnabled
  stz pppReceiveActive
  stz pppFrameReady
  jsr pppSnapshotEnd
  plb
  rts
.endproc

; Permanent fixture for the autonomous connected-mode NO CARRIER boundary.
;
; Output:
;   Carry clear, A=$00: passed
;   Carry set, A=$66-$69: failed step
.proc pppCarrierLossRunSelfTest
  .a8
  .i16

  phb
  phx
  setDBR $7e
  lda modemDriverState
  sta pppCarrierTestSavedModemState
  lda modemSessionLastResult
  sta pppCarrierTestSavedSessionResult
  lda modemSessionLineLength
  sta pppCarrierTestSavedLineLength

  jsr pppReceiveInitialize
  lda #MODEM_STATE_CONNECTED
  sta modemDriverState
  lda #$01
  sta pppReceiveEnabled
  sta pppReceiveActive

  setDBR .bankbyte(pppCarrierLossSelfTestLine)
  ldx #$0000
@feed:
  lda pppCarrierLossSelfTestLine, x
  jsr pppReceivePushConnectedByte
  cpx #(pppCarrierLossSelfTestLineEnd - pppCarrierLossSelfTestLine - 1)
  beq @final
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$66
  bra @fail
:
  inx
  bra @feed

@final:
  cmp #PPP_EVENT_CARRIER_LOST
  beq :+
  lda #$67
  bra @fail
:
  setDBR $7e
  lda modemDriverState
  cmp #MODEM_STATE_READY
  bne @fail68
  lda modemSessionLastResult
  cmp #MODEM_SESSION_RESULT_NO_CARRIER
  bne @fail68
  lda pppReceiveEnabled
  ora pppReceiveActive
  ora pppFrameReady
  bne @fail68
  lda pppReceiveLastEvent
  cmp #PPP_EVENT_CARRIER_LOST
  bne @fail68

  m16
  lda pppCarrierLossCount
  cmp #$0001
  bne @fail69_16
  lda pppCarrierLossCount + 2
  bne @fail69_16
  m8
  jsr @cleanup
  lda #$00
  clc
  bra @return

@fail69_16:
  m8
  lda #$69
  bra @fail
@fail68:
  lda #$68
@fail:
  pha
  setDBR $7e
  jsr @cleanup
  pla
  sec

@return:
  plx
  plb
  rts

@cleanup:
  .a8
  jsr pppReceiveInitialize
  lda pppCarrierTestSavedModemState
  sta modemDriverState
  lda pppCarrierTestSavedSessionResult
  sta modemSessionLastResult
  lda pppCarrierTestSavedLineLength
  sta modemSessionLineLength
  rts
.endproc

; Feed one raw byte and update permanent receive diagnostics.
;
; Input A=raw byte, output A=PPP_EVENT_*. Preserves X, Y, DBR.
.proc pppReceivePushByte
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  jsr pppDecoderPush
  pppIncrement32 pppReceiveByteCount
  cmp #PPP_EVENT_NONE
  beq return

  sta pppReceiveLastEvent
  cmp #PPP_EVENT_FRAME
  beq frame
  cmp #PPP_EVENT_FCS_ERROR
  beq fcsError
  cmp #PPP_EVENT_INVALID
  beq invalid
  cmp #PPP_EVENT_OVERFLOW
  beq overflow
  bra return

frame:
  lda #$01
  sta pppFrameReady
  pppIncrement32 pppReceiveFrameCount
  lda #PPP_EVENT_FRAME
  bra return

fcsError:
  pppIncrement32 pppReceiveFcsErrorCount
  lda #PPP_EVENT_FCS_ERROR
  bra return

invalid:
  lda pppLastInvalidReason
  sta pppReceiveLastInvalidReason
  pppIncrement32 pppReceiveInvalidCount
  lda #PPP_EVENT_INVALID
  bra return

overflow:
  pppIncrement32 pppReceiveOverflowCount
  lda #PPP_EVENT_OVERFLOW

return:
  jsr pppSnapshotEnd
  plb
  rts
.endproc

pppCarrierLossSelfTestLine:
  .byte PPP_FLAG_SEQUENCE, 'N'
  .byte 'N', 'O', ' ', 'C', 'A', 'R', 'R', 'I', 'E', 'R', $0d, $0a
pppCarrierLossSelfTestLineEnd:

; Release the completed frame buffer after the upper layer has consumed it.
.proc pppReleaseFrame
  .a8
  .i8

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  stz pppFrameReady
  jsr pppSnapshotEnd
  plb
  rts
.endproc
