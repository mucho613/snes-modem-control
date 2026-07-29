.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import modemDriverState
.import modemReadByte
.import pppDecoderReset, pppDecoderPush
.import pppLastInvalidReason
.import pppReceiveEnabled, pppReceiveActive, pppFrameReady, pppReceiveLastEvent
.import pppReceiveLastInvalidReason, pppReceiveDrainRemaining
.import pppReceiveByteCount, pppReceiveFrameCount, pppReceiveFcsErrorCount
.import pppReceiveInvalidCount, pppReceiveOverflowCount
.import pppReceiveDrainBudgetYieldCount

.export pppReceiveInitialize, pppReceivePoll
.export pppReceiveStart, pppReceiveStop
.export pppReceivePushByte, pppReleaseFrame

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

  sep #$30
  .a8
  .i8
  lda pppReceiveEnabled
  bne @checkConnected
  stz pppReceiveActive
  jmp done

@checkConnected:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq connected
  stz pppReceiveActive
  jmp done

connected:
  lda pppReceiveActive
  bne checkFrameOwnership
  lda #$01
  sta pppReceiveActive
  stz pppFrameReady
  rep #$10
  .i16
  jsr pppDecoderReset
  sep #$10
  .i8

checkFrameOwnership:
  lda pppFrameReady
  bne done

  lda #PPP_RECEIVE_DRAIN_BUDGET
  sta pppReceiveDrainRemaining

drain:
  jsr modemReadByte
  bcs done
  rep #$10
  .i16
  jsr pppReceivePushByte
  sep #$10
  .i8

  lda pppFrameReady
  bne done
  dec pppReceiveDrainRemaining
  bne drain
  pppIncrement32 pppReceiveDrainBudgetYieldCount

done:
  rep #$30
  .a16
  .i16
  ply
  plx
  plb
  pla
  rts
.endproc

; Explicit ownership switch. Raw binary tests retain the NDM24 RX ring while
; disabled; the future link state machine enables PPP after CONNECT.
.proc pppReceiveStart
  .a8
  .i8

  phb
  setDBR $7e
  lda #$01
  sta pppReceiveEnabled
  stz pppReceiveActive
  stz pppFrameReady
  plb
  rts
.endproc

.proc pppReceiveStop
  .a8
  .i8

  phb
  setDBR $7e
  stz pppReceiveEnabled
  stz pppReceiveActive
  stz pppFrameReady
  plb
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
  plb
  rts
.endproc

; Release the completed frame buffer after the upper layer has consumed it.
.proc pppReleaseFrame
  .a8
  .i8

  phb
  setDBR $7e
  stz pppFrameReady
  plb
  rts
.endproc
