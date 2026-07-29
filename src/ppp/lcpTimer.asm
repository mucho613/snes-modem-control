.include "../macro/utility.asm"
.include "constants.inc"

.code

.import frameCounter
.import pppSnapshotBegin, pppSnapshotEnd
.import pppLcpInitialize, pppLcpOpen, pppLcpBuildPending
.import pppTransmitInitialize
.import pppLcpState, pppLcpRequestIdentifier
.import pppLcpRestartRemaining, pppLcpPendingAction
.import pppLcpPeerFlags, pppLcpPeerMru, pppLcpPeerAccm
.import pppLcpPeerMagic, pppLcpRestartDeadline, pppLcpTimerActive

.export pppLcpArmRestartTimer, pppLcpPollTimeout, pppLcpLowerDown
.export pppLcpTimerRunSelfTest

.macro pppLcpTimerRequireEqual failure
  beq :+
  jmp failure
:
.endmacro

.macro pppLcpTimerRequireNonzero failure
  bne :+
  jmp failure
:
.endmacro

.macro pppLcpTimerRequireCarryClear failure
  bcc :+
  jmp failure
:
.endmacro

.macro pppLcpTimerRequireCarrySet failure
  bcs :+
  jmp failure
:
.endmacro

; Arm the restart timer from the NMI-maintained 16-bit frame counter.
; The 180-frame interval is below half the counter range, so subtraction can
; distinguish a future deadline across wrap-around.
.proc pppLcpArmRestartTimer
  .a8
  .i16

  phb
  setDBR $7e
  rep #$20
  .a16
  lda frameCounter
  jsr pppLcpArmRestartTimerAt
  .a8
  plb
  rts
.endproc

; Input A16=current frame. Output A8, timer active.
.proc pppLcpArmRestartTimerAt
  .a16
  .i16

  clc
  adc #PPP_LCP_RESTART_INTERVAL_FRAMES
  sta pppLcpRestartDeadline
  sep #$20
  .a8
  lda #$01
  sta pppLcpTimerActive
  rts
.endproc

; Poll the restart timer using the current frame counter.
;
; Output carry set when timeout caused a retransmission or Stopped transition;
; carry clear when no state change was needed.
.proc pppLcpPollTimeout
  .a8
  .i16

  phb
  setDBR $7e
  rep #$20
  .a16
  lda frameCounter
  jsr pppLcpPollTimeoutAt
  .a8
  plb
  rts
.endproc

; Input A16=current frame. Uses wrap-safe 16-bit deadline comparison.
.proc pppLcpPollTimeoutAt
  .a16
  .i16

  phb
  setDBR $7e
  pha
  sep #$20
  .a8
  lda pppLcpTimerActive
  bne :+
  rep #$20
  .a16
  pla
  jmp @unchanged
:
  rep #$20
  .a16
  pla
  sec
  sbc pppLcpRestartDeadline
  bmi @unchanged

  sep #$20
  .a8
  lda pppLcpState
  cmp #PPP_LCP_STATE_REQUEST_SENT
  beq @configuring
  cmp #PPP_LCP_STATE_ACK_RECEIVED
  beq @configuring
  cmp #PPP_LCP_STATE_ACK_SENT
  beq @configuring
  stz pppLcpTimerActive
  plb
  clc
  rts

@configuring:
  .a8
  jsr pppSnapshotBegin
  lda pppLcpRestartRemaining
  beq @finished
  dec pppLcpRestartRemaining
  lda pppLcpState
  cmp #PPP_LCP_STATE_ACK_RECEIVED
  bne :+
  lda #PPP_LCP_STATE_REQUEST_SENT
  sta pppLcpState
:
  lda #PPP_LCP_ACTION_CONFIGURE_REQUEST
  sta pppLcpPendingAction
  stz pppLcpTimerActive
  jsr pppSnapshotEnd
  plb
  sec
  rts

@finished:
  .a8
  lda #PPP_LCP_STATE_STOPPED
  sta pppLcpState
  stz pppLcpRestartRemaining
  stz pppLcpPendingAction
  stz pppLcpTimerActive
  jsr pppSnapshotEnd
  plb
  sec
  rts

@unchanged:
  .a16
  sep #$20
  .a8
  plb
  clc
  rts
.endproc

; Reset LCP when the modem carrier/lower layer is no longer available.
.proc pppLcpLowerDown
  .a8
  .i16

  phb
  setDBR $7e
  jsr pppSnapshotBegin
  lda #PPP_LCP_STATE_CLOSED
  sta pppLcpState
  stz pppLcpRestartRemaining
  stz pppLcpPendingAction
  stz pppLcpTimerActive
  stz pppLcpPeerFlags
  rep #$20
  .a16
  lda #PPP_DEFAULT_MRU
  sta pppLcpPeerMru
  lda #$ffff
  sta pppLcpPeerAccm
  sta pppLcpPeerAccm + 2
  stz pppLcpPeerMagic
  stz pppLcpPeerMagic + 2
  sep #$20
  .a8
  jsr pppSnapshotEnd
  plb
  rts
.endproc

; Deterministic restart timer fixtures. No real-time wait or live peer needed.
;
; Output:
;   Carry clear, A=$00: passed
;   Carry set, A=$50-$55: failed step
.proc pppLcpTimerRunSelfTest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  jsr pppLcpOpen

  ; Initial/new requests reserve nine retries for Max-Configure=10.
  lda pppLcpRestartRemaining
  cmp #(PPP_LCP_DEFAULT_MAX_CONFIGURE - 1)
  pppLcpTimerRequireEqual @fail50
  jsr pppLcpBuildPending
  pppLcpTimerRequireCarryClear @fail50
  lda pppLcpTimerActive
  pppLcpTimerRequireNonzero @fail50
  lda pppLcpPendingAction
  pppLcpTimerRequireEqual @fail50
  jsr pppTransmitInitialize

  ; Arm just before 16-bit wrap and verify the exact wrapped deadline.
  rep #$20
  .a16
  lda #$fff0
  jsr pppLcpArmRestartTimerAt
  .a8
  lda pppLcpTimerActive
  pppLcpTimerRequireNonzero @fail50
  rep #$20
  .a16
  lda pppLcpRestartDeadline
  cmp #$00a4
  pppLcpTimerRequireEqual @fail50_16

  ; One frame before the deadline does nothing.
  lda #$00a3
  jsr pppLcpPollTimeoutAt
  .a8
  pppLcpTimerRequireCarryClear @fail51
  lda pppLcpPendingAction
  pppLcpTimerRequireEqual @fail51

  ; Expire the already-sent request at the exact deadline.
  rep #$20
  .a16
  lda #$00a4
  jsr pppLcpPollTimeoutAt
  .a8
  pppLcpTimerRequireCarrySet @fail52
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_REQUEST
  pppLcpTimerRequireEqual @fail52
  lda pppLcpRestartRemaining
  cmp #(PPP_LCP_DEFAULT_MAX_CONFIGURE - 2)
  pppLcpTimerRequireEqual @fail52
  lda pppLcpTimerActive
  pppLcpTimerRequireEqual @fail52
  lda pppLcpRequestIdentifier
  pppLcpTimerRequireEqual @fail52

  ; Exhaustion enters Stopped without allocating a new Identifier.
  stz pppLcpPendingAction
  stz pppLcpRestartRemaining
  rep #$20
  .a16
  lda #$0100
  jsr pppLcpArmRestartTimerAt
  .a8
  rep #$20
  .a16
  lda pppLcpRestartDeadline
  jsr pppLcpPollTimeoutAt
  .a8
  pppLcpTimerRequireCarrySet @fail53
  lda pppLcpState
  cmp #PPP_LCP_STATE_STOPPED
  pppLcpTimerRequireEqual @fail53
  lda pppLcpPendingAction
  pppLcpTimerRequireEqual @fail53
  lda pppLcpTimerActive
  pppLcpTimerRequireEqual @fail53
  lda pppLcpRequestIdentifier
  pppLcpTimerRequireEqual @fail53

  ; Ack-Received falls back to Request-Sent on timeout.
  lda #PPP_LCP_STATE_ACK_RECEIVED
  sta pppLcpState
  lda #$01
  sta pppLcpRestartRemaining
  rep #$20
  .a16
  lda #$0200
  jsr pppLcpArmRestartTimerAt
  .a8
  rep #$20
  .a16
  lda pppLcpRestartDeadline
  jsr pppLcpPollTimeoutAt
  .a8
  pppLcpTimerRequireCarrySet @fail54
  lda pppLcpState
  cmp #PPP_LCP_STATE_REQUEST_SENT
  pppLcpTimerRequireEqual @fail54
  lda pppLcpRestartRemaining
  pppLcpTimerRequireEqual @fail54

  ; Lower-down cancels timing and restores peer defaults.
  lda #PPP_LCP_STATE_OPENED
  sta pppLcpState
  lda #$ff
  sta pppLcpPeerFlags
  sta pppLcpTimerActive
  jsr pppLcpLowerDown
  lda pppLcpState
  cmp #PPP_LCP_STATE_CLOSED
  pppLcpTimerRequireEqual @fail55
  lda pppLcpPeerFlags
  ora pppLcpTimerActive
  ora pppLcpPendingAction
  pppLcpTimerRequireEqual @fail55
  rep #$20
  .a16
  lda pppLcpPeerMru
  cmp #PPP_DEFAULT_MRU
  pppLcpTimerRequireEqual @fail55_16
  lda pppLcpPeerAccm
  and pppLcpPeerAccm + 2
  cmp #$ffff
  pppLcpTimerRequireEqual @fail55_16

  sep #$20
  .a8
  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  lda #$00
  clc
  bra @return

@fail50_16:
  .a16
  sep #$20
  .a8
@fail50:
  lda #$50
  bra @fail
@fail51:
  .a8
  lda #$51
  bra @fail
@fail52:
  .a8
  lda #$52
  bra @fail
@fail53:
  .a8
  lda #$53
  bra @fail
@fail54:
  .a8
  lda #$54
  bra @fail
@fail55_16:
  .a16
  sep #$20
  .a8
@fail55:
  lda #$55

@fail:
  pha
  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  pla
  sec

@return:
  ply
  plx
  plb
  rts
.endproc
