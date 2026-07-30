.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import modemDriverState
.import modemQueueByte
.import pppSnapshotBegin, pppSnapshotEnd
.import pppTransmitActive, pppTransmitStage, pppTransmitEscapeSecond
.import pppTransmitLength, pppTransmitPosition, pppTransmitFcs
.import pppTransmitLogicalByte, pppTransmitFillRemaining
.import pppTransmitLastWireByte, pppTransmitWireByteCount
.import pppTransmitFrameCount, pppTransmitBackpressureCount
.import pppTransmitAbortCount
.import pppTransmitBuffer

.export pppTransmitInitialize, pppTransmitBegin, pppTransmitPoll
.export pppTransmitAbort
.export pppTransmitPeek, pppTransmitAdvance

.proc pppTransmitInitialize
  .a8
  .i16

  phb
  setDBR $7e
  stz pppTransmitActive
  stz pppTransmitStage
  stz pppTransmitEscapeSecond
  stz pppTransmitLogicalByte
  stz pppTransmitFillRemaining
  stz pppTransmitLastWireByte
  stz pppTransmitLength
  stz pppTransmitLength + 1
  stz pppTransmitPosition
  stz pppTransmitPosition + 1
  stz pppTransmitFcs
  stz pppTransmitFcs + 1
  stz pppTransmitWireByteCount
  stz pppTransmitWireByteCount + 1
  stz pppTransmitWireByteCount + 2
  stz pppTransmitWireByteCount + 3
  stz pppTransmitFrameCount
  stz pppTransmitFrameCount + 1
  stz pppTransmitFrameCount + 2
  stz pppTransmitFrameCount + 3
  stz pppTransmitBackpressureCount
  stz pppTransmitBackpressureCount + 1
  stz pppTransmitBackpressureCount + 2
  stz pppTransmitBackpressureCount + 3
  stz pppTransmitAbortCount
  stz pppTransmitAbortCount + 1
  stz pppTransmitAbortCount + 2
  stz pppTransmitAbortCount + 3
  plb
  rts
.endproc

; Begin encoding pppTransmitBuffer.
;
; Input A16=unescaped frame length, excluding FCS and Flags.
; Carry clear means accepted; carry set means busy or too long.
.proc pppTransmitBegin
  .a16
  .i16

  phb
  setDBR $7e
  cmp #PPP_MAX_TRANSMIT_FRAME_LENGTH + 1
  bcs invalid
  pha
  m8
  lda pppTransmitActive
  bne busy
  m16
  pla
  pha
  m8
  jsr pppSnapshotBegin
  m16
  pla
  sta pppTransmitLength
  stz pppTransmitPosition
  lda #PPP_INITIAL_FCS16
  sta pppTransmitFcs
  m8
  stz pppTransmitEscapeSecond
  lda #PPP_TRANSMIT_STAGE_OPENING_FLAG
  sta pppTransmitStage
  lda #$01
  sta pppTransmitActive
  jsr pppSnapshotEnd
  m16
  plb
  clc
  rts

busy:
  m16
  pla
invalid:
  plb
  sec
  rts
.endproc

; Cancel an owned frame without resetting lifetime diagnostics.
.proc pppTransmitAbort
  .a8
  .i16

  phb
  setDBR $7e
  lda pppTransmitActive
  beq abortDone
  jsr pppSnapshotBegin
  stz pppTransmitActive
  stz pppTransmitEscapeSecond
  lda #PPP_TRANSMIT_STAGE_IDLE
  sta pppTransmitStage
  pppIncrement32 pppTransmitAbortCount
  jsr pppSnapshotEnd
abortDone:
  .a8
  plb
  rts
.endproc

; Fill the NDM24 TX ring while connected. A rejected ring write leaves the
; encoder on exactly the same wire octet for the next main-loop iteration.
.proc pppTransmitPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e

  mi8
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq connected
  lda pppTransmitActive
  beq done
  jsr pppSnapshotBegin
  stz pppTransmitActive
  stz pppTransmitEscapeSecond
  lda #PPP_TRANSMIT_STAGE_IDLE
  sta pppTransmitStage
  pppIncrement32 pppTransmitAbortCount
  jsr pppSnapshotEnd
  bra done

connected:
  lda pppTransmitActive
  beq done
  lda #PPP_TRANSMIT_FILL_BUDGET
  sta pppTransmitFillRemaining

fill:
  i16
  jsr pppTransmitPeek
  i8
  bcs done
  jsr modemQueueByte
  bcc accepted
  jsr pppSnapshotBegin
  pppIncrement32 pppTransmitBackpressureCount
  jsr pppSnapshotEnd
  bra done

accepted:
  i16
  jsr pppTransmitAdvance
  i8
  lda pppTransmitActive
  beq done
  dec pppTransmitFillRemaining
  bne fill

done:
  mi16
  ply
  plx
  plb
  pla
  rts
.endproc

; Return the next wire octet without changing encoder state.
; Carry set means no active octet. Preserves X, Y, DBR.
.proc pppTransmitPeek
  .a8
  .i16

  phb
  phx
  setDBR $7e
  lda pppTransmitStage
  cmp #PPP_TRANSMIT_STAGE_OPENING_FLAG
  beq flag
  cmp #PPP_TRANSMIT_STAGE_CLOSING_FLAG
  beq flag
  cmp #PPP_TRANSMIT_STAGE_FRAME
  beq frame
  cmp #PPP_TRANSMIT_STAGE_FCS_LOW
  beq fcsLow
  cmp #PPP_TRANSMIT_STAGE_FCS_HIGH
  beq fcsHigh
  plx
  plb
  sec
  rts

flag:
  lda #PPP_FLAG_SEQUENCE
  bra ready

frame:
  m16
  ldx pppTransmitPosition
  m8
  lda pppTransmitBuffer, x
  bra escape

fcsLow:
  lda pppTransmitFcs
  eor #$ff
  bra escape

fcsHigh:
  lda pppTransmitFcs + 1
  eor #$ff

escape:
  sta pppTransmitLogicalByte
  cmp #$20
  bcc escaped
  cmp #PPP_CONTROL_ESCAPE
  beq escaped
  cmp #PPP_FLAG_SEQUENCE
  beq escaped
  bra ready

escaped:
  lda pppTransmitEscapeSecond
  bne escapedValue
  lda #PPP_CONTROL_ESCAPE
  bra ready
escapedValue:
  lda pppTransmitLogicalByte
  eor #PPP_TRANSPARENCY_XOR

ready:
  plx
  plb
  clc
  rts
.endproc

; Commit the current wire octet after the transport accepted it.
.proc pppTransmitAdvance
  .a8
  .i16

  phb
  phx
  setDBR $7e
  jsr pppTransmitPeek
  bcc :+
  jmp inactiveReturn
:
  jsr pppSnapshotBegin
  sta pppTransmitLastWireByte
  pppIncrement32 pppTransmitWireByteCount

  lda pppTransmitStage
  cmp #PPP_TRANSMIT_STAGE_OPENING_FLAG
  beq finishOpening
  cmp #PPP_TRANSMIT_STAGE_CLOSING_FLAG
  beq finishClosing

  lda pppTransmitLogicalByte
  cmp #$20
  bcc checkEscapeHalf
  cmp #PPP_CONTROL_ESCAPE
  beq checkEscapeHalf
  cmp #PPP_FLAG_SEQUENCE
  bne finishLogical

checkEscapeHalf:
  lda pppTransmitEscapeSecond
  bne finishEscaped
  lda #$01
  sta pppTransmitEscapeSecond
  bra return

finishEscaped:
  stz pppTransmitEscapeSecond

finishLogical:
  lda pppTransmitStage
  cmp #PPP_TRANSMIT_STAGE_FRAME
  beq finishFrame
  cmp #PPP_TRANSMIT_STAGE_FCS_LOW
  beq finishFcsLow
  lda #PPP_TRANSMIT_STAGE_CLOSING_FLAG
  sta pppTransmitStage
  bra return

finishOpening:
  m16
  lda pppTransmitLength
  m8
  beq openingEmpty
  lda #PPP_TRANSMIT_STAGE_FRAME
  sta pppTransmitStage
  bra return
openingEmpty:
  lda #PPP_TRANSMIT_STAGE_FCS_LOW
  sta pppTransmitStage
  bra return

finishFrame:
  jsr pppTransmitUpdateFcs
  m16
  inc pppTransmitPosition
  lda pppTransmitPosition
  cmp pppTransmitLength
  m8
  bne return
  lda #PPP_TRANSMIT_STAGE_FCS_LOW
  sta pppTransmitStage
  bra return

finishFcsLow:
  lda #PPP_TRANSMIT_STAGE_FCS_HIGH
  sta pppTransmitStage
  bra return

finishClosing:
  lda #PPP_TRANSMIT_STAGE_COMPLETE
  sta pppTransmitStage
  stz pppTransmitActive
  pppIncrement32 pppTransmitFrameCount

return:
  jsr pppSnapshotEnd
inactiveReturn:
  plx
  plb
  rts
.endproc

.proc pppTransmitUpdateFcs
  .a8
  .i16

  lda pppTransmitLogicalByte
  m16
  and #$00ff
  eor pppTransmitFcs
  sta pppTransmitFcs
  ldx #$0008
bitLoop:
  lda pppTransmitFcs
  lsr
  bcc store
  eor #PPP_FCS16_POLYNOMIAL_REVERSED
store:
  sta pppTransmitFcs
  dex
  bne bitLoop
  m8
  rts
.endproc
