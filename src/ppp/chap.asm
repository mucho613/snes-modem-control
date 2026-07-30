.include "../macro/utility.asm"
.include "constants.inc"

.segment "BANK1_CODE"

.import pppSnapshotBeginLong, pppSnapshotEndLong
.import pppLastProtocol, pppLastFrameLength, pppFrameBuffer
.import pppTransmitActive, pppTransmitBuffer, pppTransmitBeginLong
.import pppLcpPeerFlags
.import pppPapState, pppPapCredentialFlags
.import pppPapPeerIdLength, pppPapPasswordLength
.import pppPapPeerId, pppPapPassword
.import pppPapCredentialsReady, pppPapCredentialsClearSensitive
.import pppPapScrubTransmitBuffer
.import pppChapState, pppChapLastCode, pppChapLastIdentifier
.import pppChapLastError, pppChapResponseIdentifier, pppChapFailure
.import pppChapChallengeLength, pppChapPeerNameLength, pppChapPacketLength
.import pppChapReceiveCount, pppChapTransmitCount
.import pppChapChallenge, pppChapDigest
.import pppMd5Message, pppMd5State, pppMd5Working, pppMd5Temporary
.import pppMd5MessageLength
.import pppMd5Compute

.export pppChapInitialize, pppChapLowerUp, pppChapLowerDown
.export pppChapReceiveFrame, pppChapBuildPending
.export pppAuthenticationReady, pppChapRunSelfTest

.proc pppChapInitialize
  .a8
  .i16
  phb
  setDBR $7e
  stz pppChapState
  stz pppChapLastCode
  stz pppChapLastIdentifier
  stz pppChapLastError
  stz pppChapResponseIdentifier
  stz pppChapFailure
  stz pppChapChallengeLength
  stz pppChapPeerNameLength
  m16
  stz pppChapPacketLength
  stz pppChapReceiveCount
  stz pppChapReceiveCount + 2
  stz pppChapTransmitCount
  stz pppChapTransmitCount + 2
  m8
  plb
  rtl
.endproc

; Remove Challenge, digest, secret-bearing MD5 input, and intermediate state.
.proc pppChapScrubWorkBuffers
  .a8
  .i16
  phx
  lda #$00
  ldx #$0000
@message:
  sta pppMd5Message, x
  inx
  cpx #PPP_MD5_MESSAGE_BUFFER_LENGTH
  bne @message
  ldx #$0000
@challenge:
  sta pppChapChallenge, x
  inx
  cpx #PPP_CHAP_MAXIMUM_CHALLENGE_LENGTH
  bne @challenge
  ldx #$0000
@digest:
  sta pppChapDigest, x
  sta pppMd5State, x
  sta pppMd5Working, x
  inx
  cpx #PPP_CHAP_MD5_VALUE_LENGTH
  bne @digest
  ldx #$0000
@temporary:
  sta pppMd5Temporary, x
  inx
  cpx #4
  bne @temporary
  m16
  stz pppMd5MessageLength
  m8
  plx
  rts
.endproc

.proc pppChapLowerUp
  .a8
  .i16
  phb
  setDBR $7e
  lda pppChapState
  bne @done
  jsl pppSnapshotBeginLong
  stz pppChapFailure
  lda pppLcpPeerFlags
  and #PPP_LCP_PEER_FLAG_CHAP_MD5
  beq @notRequired
  jsl pppPapCredentialsReady
  bcc @waiting
  lda #PPP_CHAP_STATE_FAILED
  sta pppChapState
  lda #PPP_CHAP_FAILURE_CREDENTIALS_MISSING
  sta pppChapFailure
  bra @publish
@waiting:
  lda #PPP_CHAP_STATE_WAITING_CHALLENGE
  sta pppChapState
  bra @publish
@notRequired:
  lda #PPP_CHAP_STATE_OPENED
  sta pppChapState
@publish:
  jsl pppSnapshotEndLong
@done:
  plb
  rtl
.endproc

.proc pppChapLowerDown
  .a8
  .i16
  phb
  phx
  setDBR $7e
  jsl pppSnapshotBeginLong
  stz pppChapState
  stz pppChapResponseIdentifier
  stz pppChapFailure
  stz pppChapChallengeLength
  stz pppChapPeerNameLength
  m16
  stz pppChapPacketLength
  m8
  jsl pppSnapshotEndLong
  jsr pppChapScrubWorkBuffers
  jsl pppPapCredentialsClearSensitive
  plx
  plb
  rtl
.endproc

; Carry clear means the selected authentication protocol has opened.
.proc pppAuthenticationReady
  .a8
  .i16
  phb
  setDBR $7e
  lda pppLcpPeerFlags
  and #PPP_LCP_PEER_FLAG_CHAP_MD5
  beq @pap
  lda pppChapState
  cmp #PPP_CHAP_STATE_OPENED
  bne @notReady
  plb
  clc
  rtl
@pap:
  lda pppPapState
  cmp #PPP_PAP_STATE_OPENED
  bne @notReady
  plb
  clc
  rtl
@notReady:
  plb
  sec
  rtl
.endproc

.macro pppChapReturnError error
  lda #error
  sta pppChapLastError
  jsl pppSnapshotEndLong
  plb
  sec
  rtl
.endmacro

.proc pppChapReceiveFrame
  .a8
  .i16
  phb
  setDBR $7e
  jsl pppSnapshotBeginLong
  pppIncrement32 pppChapReceiveCount
  stz pppChapLastCode
  stz pppChapLastIdentifier
  stz pppChapPeerNameLength
  m16
  stz pppChapPacketLength
  lda pppLastProtocol
  cmp #PPP_PROTOCOL_CHAP
  beq @headerLength
  m8
  pppChapReturnError PPP_CHAP_ERROR_WRONG_PROTOCOL
@headerLength:
  m16
  lda pppLastFrameLength
  cmp #PPP_CHAP_MINIMUM_FRAME_LENGTH
  bcs @header
  m8
  pppChapReturnError PPP_CHAP_ERROR_TRUNCATED_HEADER
@header:
  m8
  lda pppFrameBuffer + PPP_CHAP_FRAME_OFFSET
  sta pppChapLastCode
  lda pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 1
  sta pppChapLastIdentifier
  lda pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 3
  sta pppChapPacketLength
  lda pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 2
  sta pppChapPacketLength + 1
  m16
  lda pppChapPacketLength
  cmp #PPP_CHAP_HEADER_LENGTH
  bcs @available
  m8
  pppChapReturnError PPP_CHAP_ERROR_INVALID_PACKET_LENGTH
@available:
  m16
  clc
  adc #PPP_CHAP_FRAME_OFFSET
  cmp pppLastFrameLength
  bcc @code
  beq @code
  m8
  pppChapReturnError PPP_CHAP_ERROR_TRUNCATED_PACKET
@code:
  m8
  lda pppChapLastCode
  cmp #PPP_CHAP_CODE_CHALLENGE
  beq @challenge
  cmp #PPP_CHAP_CODE_SUCCESS
  bne :+
  jmp @result
:
  cmp #PPP_CHAP_CODE_FAILURE
  bne :+
  jmp @result
:
  pppChapReturnError PPP_CHAP_ERROR_UNSUPPORTED_CODE

@challenge:
  lda pppChapState
  cmp #PPP_CHAP_STATE_WAITING_CHALLENGE
  beq :+
  cmp #PPP_CHAP_STATE_WAITING_RESULT
  beq :+
  cmp #PPP_CHAP_STATE_OPENED
  beq :+
  pppChapReturnError PPP_CHAP_ERROR_UNSUPPORTED_CODE
:
  m16
  lda pppChapPacketLength
  cmp #PPP_CHAP_HEADER_LENGTH + 1
  bcs @valueLength
  m8
  pppChapReturnError PPP_CHAP_ERROR_VALUE_LENGTH_MISSING
@valueLength:
  m8
  lda pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + PPP_CHAP_HEADER_LENGTH
  beq @valueTruncated
  cmp #PPP_CHAP_MAXIMUM_CHALLENGE_LENGTH + 1
  bcs @challengeTooLong
  sta pppChapChallengeLength
  m16
  and #$00ff
  clc
  adc #PPP_CHAP_HEADER_LENGTH + 1
  cmp pppChapPacketLength
  bcc @copyChallenge
  beq @copyChallenge
@valueTruncated:
  m8
  pppChapReturnError PPP_CHAP_ERROR_VALUE_TRUNCATED
@challengeTooLong:
  pppChapReturnError PPP_CHAP_ERROR_CHALLENGE_TOO_LONG

@copyChallenge:
  m16
  ; Publish only the peer-name length. Neither peer name nor Challenge bytes
  ; are exposed through the diagnostic ABI.
  lda pppChapPacketLength
  sec
  sbc #PPP_CHAP_HEADER_LENGTH + 1
  m8
  sec
  sbc pppChapChallengeLength
  sta pppChapPeerNameLength
  i8
  ldx #$00
@copy:
  lda pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + PPP_CHAP_HEADER_LENGTH + 1, x
  sta pppChapChallenge, x
  inx
  cpx pppChapChallengeLength
  bne @copy
  i16
  stz pppChapLastError
  lda #PPP_CHAP_STATE_RESPONSE_PENDING
  sta pppChapState
  jsl pppSnapshotEndLong
  plb
  clc
  rtl

@result:
  lda pppChapState
  cmp #PPP_CHAP_STATE_WAITING_RESULT
  beq :+
  pppChapReturnError PPP_CHAP_ERROR_UNSUPPORTED_CODE
:
  lda pppChapLastIdentifier
  cmp pppChapResponseIdentifier
  beq :+
  pppChapReturnError PPP_CHAP_ERROR_IDENTIFIER_MISMATCH
:
  stz pppChapLastError
  lda pppChapLastCode
  cmp #PPP_CHAP_CODE_SUCCESS
  beq @success
  lda #PPP_CHAP_STATE_FAILED
  sta pppChapState
  lda #PPP_CHAP_FAILURE_REJECTED
  sta pppChapFailure
  bra @finishResult
@success:
  lda #PPP_CHAP_STATE_OPENED
  sta pppChapState
  stz pppChapFailure
@finishResult:
  jsl pppSnapshotEndLong
  jsl pppPapCredentialsClearSensitive
  plb
  clc
  rtl
.endproc

; Build Response = MD5(Identifier || secret || Challenge), followed by the
; staged Peer-ID as CHAP Name.
.proc pppChapBuildPending
  .a8
  .i16
  phb
  phx
  phy
  setDBR $7e
  lda pppChapState
  cmp #PPP_CHAP_STATE_RESPONSE_PENDING
  beq :+
  jmp nothingReturn
:
  lda pppTransmitActive
  beq :+
  jmp busyReturn
:
  jsl pppPapCredentialsReady
  bcc @message
  jsl pppSnapshotBeginLong
  lda #PPP_CHAP_STATE_FAILED
  sta pppChapState
  lda #PPP_CHAP_FAILURE_CREDENTIALS_MISSING
  sta pppChapFailure
  jsl pppSnapshotEndLong
  jmp nothingReturn

@message:
  lda pppChapLastIdentifier
  sta pppMd5Message
  i8
  ldx #$00
  ldy #$01
@copySecret:
  lda pppPapPassword, x
  sta pppMd5Message, y
  inx
  iny
  cpx pppPapPasswordLength
  bne @copySecret
  ldx #$00
@copyChallenge:
  lda pppChapChallenge, x
  sta pppMd5Message, y
  inx
  iny
  cpx pppChapChallengeLength
  bne @copyChallenge
  i16
  m16
  tya
  sta pppMd5MessageLength
  m8
  jsl pppMd5Compute
  ldx #$000f
@copyDigest:
  lda pppMd5State, x
  sta pppChapDigest, x
  dex
  bpl @copyDigest

  lda #$ff
  sta pppTransmitBuffer
  lda #$03
  sta pppTransmitBuffer + 1
  lda #$c2
  sta pppTransmitBuffer + 2
  lda #$23
  sta pppTransmitBuffer + 3
  lda #PPP_CHAP_CODE_RESPONSE
  sta pppTransmitBuffer + 4
  lda pppChapLastIdentifier
  sta pppTransmitBuffer + 5
  stz pppTransmitBuffer + 6
  lda pppPapPeerIdLength
  clc
  adc #PPP_CHAP_HEADER_LENGTH + 1 + PPP_CHAP_MD5_VALUE_LENGTH
  sta pppTransmitBuffer + 7
  lda #PPP_CHAP_MD5_VALUE_LENGTH
  sta pppTransmitBuffer + 8
  ldx #$0000
@emitDigest:
  lda pppChapDigest, x
  sta pppTransmitBuffer + 9, x
  inx
  cpx #PPP_CHAP_MD5_VALUE_LENGTH
  bne @emitDigest
  i8
  ldx #$00
  ldy #PPP_CHAP_FRAME_OFFSET + PPP_CHAP_HEADER_LENGTH + 1 + PPP_CHAP_MD5_VALUE_LENGTH
@emitName:
  lda pppPapPeerId, x
  sta pppTransmitBuffer, y
  inx
  iny
  cpx pppPapPeerIdLength
  bne @emitName
  i16
  m16
  tya
  jsl pppTransmitBeginLong
  m8
  bcs busyReturn
  jsl pppSnapshotBeginLong
  lda pppPapCredentialFlags
  and #PPP_PAP_CREDENTIAL_FLAG_TRANSIENT
  beq :+
  lda pppPapCredentialFlags
  ora #PPP_PAP_CREDENTIAL_FLAG_EXPOSURE_ACTIVE
  sta pppPapCredentialFlags
:
  lda pppChapLastIdentifier
  sta pppChapResponseIdentifier
  lda #PPP_CHAP_STATE_WAITING_RESULT
  sta pppChapState
  pppIncrement32 pppChapTransmitCount
  jsl pppSnapshotEndLong
  jsr pppChapScrubWorkBuffers
  bra nothingReturn

busyReturn:
  ply
  plx
  plb
  sec
  rtl
nothingReturn:
  ply
  plx
  plb
  clc
  rtl
.endproc

; Closed Challenge/Response/Success fixture. It uses only the public lab
; credential installed by pppPapCredentialsInitialize.
.proc pppChapRunSelfTest
  .a8
  .i16
  phb
  setDBR $7e
  jsl pppChapInitialize
  lda #PPP_LCP_PEER_FLAG_CHAP_MD5
  sta pppLcpPeerFlags
  ; The credential self-test restores the public closed fixture.
  jsl pppChapLowerUp
  lda pppChapState
  cmp #PPP_CHAP_STATE_WAITING_CHALLENGE
  beq :+
  jmp @failed
:
  lda pppChapFailure
  cmp #PPP_CHAP_FAILURE_NONE
  beq :+
  jmp @failedFailure
:

  m16
  lda #PPP_PROTOCOL_CHAP
  sta pppLastProtocol
  lda #PPP_CHAP_FRAME_OFFSET + PPP_CHAP_HEADER_LENGTH + 1 + 9
  sta pppLastFrameLength
  m8
  lda #PPP_CHAP_CODE_CHALLENGE
  sta pppFrameBuffer + PPP_CHAP_FRAME_OFFSET
  lda #$07
  sta pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 1
  stz pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 2
  lda #PPP_CHAP_HEADER_LENGTH + 1 + 9
  sta pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 3
  lda #9
  sta pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 4
  ldx #$0000
@challenge:
  lda f:pppChapSelfTestChallenge, x
  sta pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 5, x
  inx
  cpx #9
  bne @challenge
  jsl pppChapReceiveFrame
  bcc :+
  jmp @failed
:
  lda pppChapState
  cmp #PPP_CHAP_STATE_RESPONSE_PENDING
  beq :+
  jmp @failed
:
  jsl pppChapBuildPending
  bcc :+
  jmp @failed
:
  lda pppChapState
  cmp #PPP_CHAP_STATE_WAITING_RESULT
  beq :+
  jmp @failed
:
  lda pppTransmitBuffer + 2
  cmp #$c2
  bne @failed
  lda pppTransmitBuffer + 3
  cmp #$23
  bne @failed
  lda pppTransmitBuffer + 4
  cmp #PPP_CHAP_CODE_RESPONSE
  bne @failed
  lda pppTransmitBuffer + 5
  cmp #$07
  bne @failed
  lda pppTransmitBuffer + 8
  cmp #PPP_CHAP_MD5_VALUE_LENGTH
  bne @failed
  ldx #$0000
@digest:
  lda pppTransmitBuffer + 9, x
  cmp f:pppChapSelfTestDigest, x
  bne @failed
  inx
  cpx #PPP_CHAP_MD5_VALUE_LENGTH
  bne @digest
  jsl pppPapScrubTransmitBuffer
  stz pppTransmitActive

  lda #PPP_CHAP_CODE_SUCCESS
  sta pppFrameBuffer + PPP_CHAP_FRAME_OFFSET
  lda #$07
  sta pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 1
  stz pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 2
  lda #PPP_CHAP_HEADER_LENGTH
  sta pppFrameBuffer + PPP_CHAP_FRAME_OFFSET + 3
  m16
  lda #PPP_CHAP_FRAME_OFFSET + PPP_CHAP_HEADER_LENGTH
  sta pppLastFrameLength
  m8
  jsl pppChapReceiveFrame
  bcs @failed
  lda pppChapState
  cmp #PPP_CHAP_STATE_OPENED
  bne @failed

  jsl pppChapLowerDown
  stz pppLcpPeerFlags
  lda #$00
  plb
  clc
  rtl
@failed:
  stz pppLcpPeerFlags
  lda #$8b
  plb
  sec
  rtl
@failedFailure:
  stz pppLcpPeerFlags
  lda #$8c
  plb
  sec
  rtl
.endproc

.segment "DATA"
pppChapSelfTestChallenge:
  .byte 'c', 'h', 'a', 'l', 'l', 'e', 'n', 'g', 'e'
pppChapSelfTestDigest:
  .byte $b4, $96, $5b, $74, $8d, $8d, $25, $2e
  .byte $4a, $4f, $68, $03, $6d, $12, $ce, $50
