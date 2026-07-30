.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import modemDriverState
.import pppReceiveEnabled, pppFrameReady, pppReleaseFrame
.import pppLcpState
.import pppLastProtocol
.import pppPapState
.import pppPapLowerUp, pppPapLowerDown
.import pppPapBuildPending, pppPapReceiveFrame, pppPapPollTimeout

.export pppPapPoll

; Run after LCP polling. LCP retains ownership of LCP frames while negotiating;
; PAP owns completed non-LCP frames only after LCP reaches Opened.
.proc pppPapPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e
  sep #$20
  .a8

  lda pppReceiveEnabled
  beq @lowerDown
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  bne @lowerDown
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  bne @lowerDown

  lda pppPapState
  bne @servicePending
  jsr pppPapLowerUp

@servicePending:
  jsr pppPapBuildPending
  lda pppFrameReady
  beq @timer
  rep #$20
  .a16
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_PAP
  beq @receivePap
  sep #$20
  .a8
  ; Once PAP opens, leave non-PAP ownership to the following IPCP poll.
  lda pppPapState
  cmp #PPP_PAP_STATE_OPENED
  beq @timer
  jsr pppReleaseFrame
  bra @timer

@receivePap:
  sep #$20
  .a8
  jsr pppPapReceiveFrame
  jsr pppReleaseFrame

@timer:
  jsr pppPapPollTimeout
  jsr pppPapBuildPending
  bra @done

@lowerDown:
  lda pppPapState
  beq @done
  jsr pppPapLowerDown

@done:
  rep #$30
  .a16
  .i16
  ply
  plx
  plb
  pla
  rts
.endproc
