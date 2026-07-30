.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.segment "BANK1_CODE"

.import modemDriverState
.import pppReceiveEnabled, pppFrameReady, pppReleaseFrameLong
.import pppLcpState, pppLastProtocol
.import pppChapState
.import pppChapLowerUp, pppChapLowerDown
.import pppChapReceiveFrame, pppChapBuildPending

.export pppChapPoll

; Run after PAP polling. CHAP owns protocol $c223 until authentication opens.
.proc pppChapPoll
  .a16
  .i16
  pha
  phb
  phx
  phy
  setDBR $7e
  m8
  lda pppReceiveEnabled
  beq @lowerDown
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  bne @lowerDown
  lda pppLcpState
  cmp #PPP_LCP_STATE_OPENED
  bne @lowerDown
  lda pppChapState
  bne @service
  jsl pppChapLowerUp
@service:
  jsl pppChapBuildPending
  lda pppFrameReady
  beq @done
  m16
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_CHAP
  beq @receive
  m8
  lda pppChapState
  cmp #PPP_CHAP_STATE_OPENED
  beq @done
  jsl pppReleaseFrameLong
  bra @done
@receive:
  m8
  jsl pppChapReceiveFrame
  jsl pppReleaseFrameLong
  jsl pppChapBuildPending
  bra @done
@lowerDown:
  lda pppChapState
  beq @done
  jsl pppChapLowerDown
@done:
  mi16
  ply
  plx
  plb
  pla
  rtl
.endproc
