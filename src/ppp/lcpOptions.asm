.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppFrameBuffer, pppTransmitBuffer
.import pppLcpPacketEnd, pppLcpPacketLength
.import pppLcpPeerFlags, pppLcpPeerMru, pppLcpPeerAccm
.import pppLcpPendingAction
.import pppLcpOptionSeen, pppLcpOptionDuplicate
.import pppLcpOptionOffset, pppLcpOptionLength, pppLcpOutputCursor
.import pppLcpHasReject, pppLcpHasNak, pppLcpPeerMagic
.import pppLcpInitialize, pppTransmitInitialize

.export pppLcpEvaluatePeerRequest, pppLcpBuildPeerResponse
.export pppLcpOptionsRunSelfTest

.macro pppLcpBranchEqualOrJump failure
  beq :+
  jmp failure
:
.endmacro

; Evaluate every option in the parsed peer Configure-Request.
;
; Output A=PPP_LCP_ACTION_CONFIGURE_ACK/NAK/REJECT. Duplicate option types are
; all rejected, including the first occurrence. Reject takes precedence over
; Nak. Accepted values are published only when the complete request is Acked.
.proc pppLcpEvaluatePeerRequest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e

  ldx #$0000
@clearMaps:
  assert_m8_i16
  stz pppLcpOptionSeen, x
  stz pppLcpOptionDuplicate, x
  inx
  cpx #$0100
  bne @clearMaps

  ; First pass records duplicate types without changing option order.
  ldy #PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH
@duplicateLoop:
  assert_m8_i16
  cpy pppLcpPacketEnd
  beq @classifyStart
  lda pppFrameBuffer, y
  tax
  lda pppLcpOptionSeen, x
  beq @firstType
  lda #$01
  sta pppLcpOptionDuplicate, x
  bra @duplicateAdvance
@firstType:
  assert_m8_i16
  lda #$01
  sta pppLcpOptionSeen, x
@duplicateAdvance:
  assert_m8_i16
  jsr @advanceY
  bra @duplicateLoop

@classifyStart:
  assert_m8_i16
  stz pppLcpHasReject
  stz pppLcpHasNak
  ldy #PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH
@classifyLoop:
  assert_m8_i16
  cpy pppLcpPacketEnd
  beq @selectPacketResponse
  jsr pppLcpClassifyPeerOption
  cmp #PPP_LCP_OPTION_DISPOSITION_REJECT
  bne @checkNak
  lda #$01
  sta pppLcpHasReject
  bra @classifyAdvance
@checkNak:
  assert_m8_i16
  cmp #PPP_LCP_OPTION_DISPOSITION_NAK
  bne @classifyAdvance
  lda #$01
  sta pppLcpHasNak
@classifyAdvance:
  assert_m8_i16
  jsr @advanceY
  bra @classifyLoop

@selectPacketResponse:
  assert_m8_i16
  lda pppLcpHasReject
  beq @selectNak
  lda #PPP_LCP_ACTION_CONFIGURE_REJECT
  bra @return
@selectNak:
  assert_m8_i16
  lda pppLcpHasNak
  beq @accept
  lda #PPP_LCP_ACTION_CONFIGURE_NAK
  bra @return
@accept:
  assert_m8_i16
  jsr @commitAcceptedConfiguration
  lda #PPP_LCP_ACTION_CONFIGURE_ACK

@return:
  assert_m8_i16
  ply
  plx
  plb
  rts

; Advance Y by the current option's validated Length.
@advanceY:
  assert_m8_i16
  lda pppFrameBuffer + 1, y
  sta pppLcpOptionLength
  stz pppLcpOptionLength + 1
  m16
  tya
  clc
  adc pppLcpOptionLength
  tay
  m8
  rts

; Publish peer values only after every option was accepted.
@commitAcceptedConfiguration:
  assert_m8_i16
  stz pppLcpPeerFlags
  m16
  lda #PPP_DEFAULT_MRU
  sta pppLcpPeerMru
  lda #$ffff
  sta pppLcpPeerAccm
  sta pppLcpPeerAccm + 2
  stz pppLcpPeerMagic
  stz pppLcpPeerMagic + 2
  m8
  ldy #PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH
@commitLoop:
  assert_m8_i16
  cpy pppLcpPacketEnd
  beq @commitDone
  lda pppFrameBuffer, y
  cmp #PPP_LCP_OPTION_MRU
  beq @commitMru
  cmp #PPP_LCP_OPTION_ACCM
  beq @commitAccm
  cmp #PPP_LCP_OPTION_AUTHENTICATION
  beq @commitPap
  cmp #PPP_LCP_OPTION_MAGIC_NUMBER
  beq @commitMagic
  bra @commitAdvance

@commitMru:
  assert_m8_i16
  lda pppFrameBuffer + 3, y
  sta pppLcpPeerMru
  lda pppFrameBuffer + 2, y
  sta pppLcpPeerMru + 1
  lda pppLcpPeerFlags
  ora #PPP_LCP_PEER_FLAG_MRU
  sta pppLcpPeerFlags
  bra @commitAdvance

@commitAccm:
  assert_m8_i16
  lda pppFrameBuffer + 5, y
  sta pppLcpPeerAccm
  lda pppFrameBuffer + 4, y
  sta pppLcpPeerAccm + 1
  lda pppFrameBuffer + 3, y
  sta pppLcpPeerAccm + 2
  lda pppFrameBuffer + 2, y
  sta pppLcpPeerAccm + 3
  lda pppLcpPeerFlags
  ora #PPP_LCP_PEER_FLAG_ACCM
  sta pppLcpPeerFlags
  bra @commitAdvance

@commitPap:
  assert_m8_i16
  lda pppLcpPeerFlags
  ora #PPP_LCP_PEER_FLAG_PAP
  sta pppLcpPeerFlags
  bra @commitAdvance

@commitMagic:
  assert_m8_i16
  lda pppFrameBuffer + 5, y
  sta pppLcpPeerMagic
  lda pppFrameBuffer + 4, y
  sta pppLcpPeerMagic + 1
  lda pppFrameBuffer + 3, y
  sta pppLcpPeerMagic + 2
  lda pppFrameBuffer + 2, y
  sta pppLcpPeerMagic + 3
  lda pppLcpPeerFlags
  ora #PPP_LCP_PEER_FLAG_MAGIC_NUMBER
  sta pppLcpPeerFlags

@commitAdvance:
  assert_m8_i16
  jsr @advanceY
  jmp @commitLoop
@commitDone:
  assert_m8_i16
  rts
.endproc

; Fixed peer-option policy fixtures.
;
; Output:
;   Carry clear, A=$00: passed
;   Carry set, A=$40-$43: failed fixture
.proc pppLcpOptionsRunSelfTest
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e
  jsr pppLcpInitialize
  jsr pppTransmitInitialize

  ; All supported values are accepted and committed atomically:
  ; MRU 1492, ACCM 0, PAP, Magic-Number $12345678.
  lda #$18
  jsr @preparePacket
  lda #$41
  sta pppFrameBuffer + 5
  lda #PPP_LCP_OPTION_MRU
  sta pppFrameBuffer + 8
  lda #$04
  sta pppFrameBuffer + 9
  lda #$05
  sta pppFrameBuffer + 10
  lda #$d4
  sta pppFrameBuffer + 11
  lda #PPP_LCP_OPTION_ACCM
  sta pppFrameBuffer + 12
  lda #$06
  sta pppFrameBuffer + 13
  stz pppFrameBuffer + 14
  stz pppFrameBuffer + 15
  stz pppFrameBuffer + 16
  stz pppFrameBuffer + 17
  lda #PPP_LCP_OPTION_AUTHENTICATION
  sta pppFrameBuffer + 18
  lda #$04
  sta pppFrameBuffer + 19
  lda #$c0
  sta pppFrameBuffer + 20
  lda #$23
  sta pppFrameBuffer + 21
  lda #PPP_LCP_OPTION_MAGIC_NUMBER
  sta pppFrameBuffer + 22
  lda #$06
  sta pppFrameBuffer + 23
  lda #$12
  sta pppFrameBuffer + 24
  lda #$34
  sta pppFrameBuffer + 25
  lda #$56
  sta pppFrameBuffer + 26
  lda #$78
  sta pppFrameBuffer + 27
  jsr pppLcpEvaluatePeerRequest
  cmp #PPP_LCP_ACTION_CONFIGURE_ACK
  pppLcpBranchEqualOrJump @fail40
  lda pppLcpPeerFlags
  cmp #(PPP_LCP_PEER_FLAG_MRU | PPP_LCP_PEER_FLAG_ACCM | PPP_LCP_PEER_FLAG_PAP | PPP_LCP_PEER_FLAG_MAGIC_NUMBER)
  pppLcpBranchEqualOrJump @fail40
  m16
  lda pppLcpPeerMru
  cmp #$05d4
  pppLcpBranchEqualOrJump @fail40_16
  lda pppLcpPeerAccm
  ora pppLcpPeerAccm + 2
  pppLcpBranchEqualOrJump @fail40_16
  lda pppLcpPeerMagic
  cmp #$5678
  pppLcpBranchEqualOrJump @fail40_16
  lda pppLcpPeerMagic + 2
  cmp #$1234
  pppLcpBranchEqualOrJump @fail40_16
  m8
  ; Invalid MRU and CHAP are Nak candidates in original option order.
  lda #$0d
  jsr @preparePacket
  lda #$42
  sta pppFrameBuffer + 5
  lda #PPP_LCP_OPTION_MRU
  sta pppFrameBuffer + 8
  lda #$04
  sta pppFrameBuffer + 9
  stz pppFrameBuffer + 10
  stz pppFrameBuffer + 11
  lda #PPP_LCP_OPTION_AUTHENTICATION
  sta pppFrameBuffer + 12
  lda #$05
  sta pppFrameBuffer + 13
  lda #$c2
  sta pppFrameBuffer + 14
  lda #$23
  sta pppFrameBuffer + 15
  lda #$05
  sta pppFrameBuffer + 16
  jsr pppLcpEvaluatePeerRequest
  cmp #PPP_LCP_ACTION_CONFIGURE_NAK
  pppLcpBranchEqualOrJump @fail41
  sta pppLcpPendingAction
  m16
  jsr pppLcpBuildPeerResponse
  assert_m16_i16
  cmp #$0010
  pppLcpBranchEqualOrJump @fail41_16
  m8
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CONFIGURE_NAK
  pppLcpBranchEqualOrJump @fail41
  lda pppTransmitBuffer + 5
  cmp #$42
  pppLcpBranchEqualOrJump @fail41
  lda pppTransmitBuffer + 7
  cmp #$0c
  pppLcpBranchEqualOrJump @fail41
  lda pppTransmitBuffer + 8
  cmp #PPP_LCP_OPTION_MRU
  pppLcpBranchEqualOrJump @fail41
  lda pppTransmitBuffer + 10
  cmp #$05
  pppLcpBranchEqualOrJump @fail41
  lda pppTransmitBuffer + 11
  cmp #$dc
  pppLcpBranchEqualOrJump @fail41
  lda pppTransmitBuffer + 12
  cmp #PPP_LCP_OPTION_AUTHENTICATION
  pppLcpBranchEqualOrJump @fail41
  lda pppTransmitBuffer + 14
  cmp #$c0
  pppLcpBranchEqualOrJump @fail41
  lda pppTransmitBuffer + 15
  cmp #$23
  pppLcpBranchEqualOrJump @fail41

  ; Reject takes precedence over the CHAP Nak and includes only the exact
  ; unsupported PFC and unknown options.
  lda #$0e
  jsr @preparePacket
  lda #$43
  sta pppFrameBuffer + 5
  lda #PPP_LCP_OPTION_AUTHENTICATION
  sta pppFrameBuffer + 8
  lda #$05
  sta pppFrameBuffer + 9
  lda #$c2
  sta pppFrameBuffer + 10
  lda #$23
  sta pppFrameBuffer + 11
  lda #$05
  sta pppFrameBuffer + 12
  lda #PPP_LCP_OPTION_PROTOCOL_FIELD_COMPRESSION
  sta pppFrameBuffer + 13
  lda #$02
  sta pppFrameBuffer + 14
  lda #$63
  sta pppFrameBuffer + 15
  lda #$03
  sta pppFrameBuffer + 16
  lda #$ab
  sta pppFrameBuffer + 17
  jsr pppLcpEvaluatePeerRequest
  cmp #PPP_LCP_ACTION_CONFIGURE_REJECT
  pppLcpBranchEqualOrJump @fail42
  sta pppLcpPendingAction
  m16
  jsr pppLcpBuildPeerResponse
  assert_m16_i16
  cmp #$000d
  pppLcpBranchEqualOrJump @fail42_16
  m8
  lda pppTransmitBuffer + 4
  cmp #PPP_LCP_CODE_CONFIGURE_REJECT
  pppLcpBranchEqualOrJump @fail42
  lda pppTransmitBuffer + 5
  cmp #$43
  pppLcpBranchEqualOrJump @fail42
  lda pppTransmitBuffer + 7
  cmp #$09
  pppLcpBranchEqualOrJump @fail42
  lda pppTransmitBuffer + 8
  cmp #PPP_LCP_OPTION_PROTOCOL_FIELD_COMPRESSION
  pppLcpBranchEqualOrJump @fail42
  lda pppTransmitBuffer + 9
  cmp #$02
  pppLcpBranchEqualOrJump @fail42
  lda pppTransmitBuffer + 10
  cmp #$63
  pppLcpBranchEqualOrJump @fail42
  lda pppTransmitBuffer + 11
  cmp #$03
  pppLcpBranchEqualOrJump @fail42
  lda pppTransmitBuffer + 12
  cmp #$ab
  pppLcpBranchEqualOrJump @fail42

  ; Every occurrence of a duplicated type is rejected verbatim.
  lda #$0c
  jsr @preparePacket
  lda #$44
  sta pppFrameBuffer + 5
  lda #PPP_LCP_OPTION_MRU
  sta pppFrameBuffer + 8
  lda #$04
  sta pppFrameBuffer + 9
  lda #$05
  sta pppFrameBuffer + 10
  lda #$dc
  sta pppFrameBuffer + 11
  lda #PPP_LCP_OPTION_MRU
  sta pppFrameBuffer + 12
  lda #$04
  sta pppFrameBuffer + 13
  lda #$05
  sta pppFrameBuffer + 14
  lda #$d4
  sta pppFrameBuffer + 15
  jsr pppLcpEvaluatePeerRequest
  cmp #PPP_LCP_ACTION_CONFIGURE_REJECT
  pppLcpBranchEqualOrJump @fail43
  sta pppLcpPendingAction
  m16
  jsr pppLcpBuildPeerResponse
  assert_m16_i16
  cmp #$0010
  pppLcpBranchEqualOrJump @fail43_16
  m8
  lda pppTransmitBuffer + 7
  cmp #$0c
  pppLcpBranchEqualOrJump @fail43
  ldx #$0008
@duplicateCompare:
  lda pppTransmitBuffer, x
  cmp pppFrameBuffer, x
  pppLcpBranchEqualOrJump @fail43
  inx
  cpx #$0010
  bne @duplicateCompare

  jsr pppLcpInitialize
  jsr pppTransmitInitialize
  lda #$00
  clc
  bra @return

@fail40_16:
  assert_m16_i16
  m8
@fail40:
  lda #$40
  bra @fail
@fail41_16:
  assert_m16_i16
  m8
@fail41:
  lda #$41
  bra @fail
@fail42_16:
  assert_m16_i16
  m8
@fail42:
  lda #$42
  bra @fail
@fail43_16:
  assert_m16_i16
  m8
@fail43:
  lda #$43

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

; Input A8=LCP packet length. Establish the already-validated packet bounds.
@preparePacket:
  assert_m8_i16
  sta pppLcpPacketLength
  stz pppLcpPacketLength + 1
  sta pppFrameBuffer + 7
  stz pppFrameBuffer + 6
  lda #PPP_LCP_CODE_CONFIGURE_REQUEST
  sta pppFrameBuffer + 4
  m16
  lda pppLcpPacketLength
  clc
  adc #PPP_LCP_FRAME_OFFSET
  sta pppLcpPacketEnd
  m8
  rts
.endproc

; Input Y=absolute option offset in pppFrameBuffer.
; Output A=PPP_LCP_OPTION_DISPOSITION_*. Preserves X and Y.
.proc pppLcpClassifyPeerOption
  .a8
  .i16

  phx
  lda pppFrameBuffer, y
  tax
  lda pppLcpOptionDuplicate, x
  bne @reject

  txa
  cmp #PPP_LCP_OPTION_MRU
  beq @mru
  cmp #PPP_LCP_OPTION_ACCM
  beq @accm
  cmp #PPP_LCP_OPTION_AUTHENTICATION
  beq @authentication
  cmp #PPP_LCP_OPTION_MAGIC_NUMBER
  beq @magic
  bra @reject

@mru:
  assert_m8_i16
  lda pppFrameBuffer + 1, y
  cmp #$04
  bne @nak
  lda pppFrameBuffer + 2, y
  ora pppFrameBuffer + 3, y
  beq @nak
  bra @ack

@accm:
  assert_m8_i16
  lda pppFrameBuffer + 1, y
  cmp #$06
  beq @ack
  bra @nak

@authentication:
  assert_m8_i16
  lda pppFrameBuffer + 1, y
  cmp #$04
  bne @nak
  lda pppFrameBuffer + 2, y
  cmp #$c0
  bne @nak
  lda pppFrameBuffer + 3, y
  cmp #$23
  bne @nak
  bra @ack

@magic:
  assert_m8_i16
  lda pppFrameBuffer + 1, y
  cmp #$06
  bne @reject
  lda pppFrameBuffer + 2, y
  ora pppFrameBuffer + 3, y
  ora pppFrameBuffer + 4, y
  ora pppFrameBuffer + 5, y
  beq @reject

@ack:
  assert_m8_i16
  plx
  lda #PPP_LCP_OPTION_DISPOSITION_ACK
  rts
@nak:
  assert_m8_i16
  plx
  lda #PPP_LCP_OPTION_DISPOSITION_NAK
  rts
@reject:
  assert_m8_i16
  plx
  lda #PPP_LCP_OPTION_DISPOSITION_REJECT
  rts
.endproc

; Build a selective Configure-Nak or Configure-Reject in pppTransmitBuffer.
; The option maps must still describe the retained peer request.
;
; Output A16=complete unescaped PPP frame length.
.proc pppLcpBuildPeerResponse
  .a16
  .i16

  phb
  phx
  phy
  setDBR $7e

  m8
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_NAK
  beq @nakCode
  lda #PPP_LCP_CODE_CONFIGURE_REJECT
  bra @storeCode
@nakCode:
  assert_m8_i16
  lda #PPP_LCP_CODE_CONFIGURE_NAK
@storeCode:
  assert_m8_i16
  sta pppTransmitBuffer + 4
  lda pppFrameBuffer + 5
  sta pppTransmitBuffer + 5
  m16
  lda #PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH
  sta pppLcpOutputCursor
  ldy #PPP_LCP_FRAME_OFFSET + PPP_LCP_HEADER_LENGTH

@optionLoop:
  assert_m16_i16
  cpy pppLcpPacketEnd
  bne :+
  jmp @finish
:
  m8
  jsr pppLcpClassifyPeerOption
  pha
  lda pppLcpPendingAction
  cmp #PPP_LCP_ACTION_CONFIGURE_REJECT
  beq @maybeReject
  pla
  cmp #PPP_LCP_OPTION_DISPOSITION_NAK
  beq @writeNak
  jmp @advanceInput

@maybeReject:
  assert_m8_i16
  pla
  cmp #PPP_LCP_OPTION_DISPOSITION_REJECT
  beq :+
  jmp @advanceInput
:
  jmp @copyInputOption

@writeNak:
  assert_m8_i16
  lda pppFrameBuffer, y
  cmp #PPP_LCP_OPTION_MRU
  beq @writeMruNak
  cmp #PPP_LCP_OPTION_ACCM
  beq @writeAccmNak
  ; Authentication is the only remaining Nak disposition.
  ldx pppLcpOutputCursor
  lda #PPP_LCP_OPTION_AUTHENTICATION
  sta pppTransmitBuffer, x
  lda #$04
  sta pppTransmitBuffer + 1, x
  lda #$c0
  sta pppTransmitBuffer + 2, x
  lda #$23
  sta pppTransmitBuffer + 3, x
  m16
  lda pppLcpOutputCursor
  clc
  adc #$0004
  sta pppLcpOutputCursor
  m8
  bra @advanceInput

@writeMruNak:
  assert_m8_i16
  ldx pppLcpOutputCursor
  lda #PPP_LCP_OPTION_MRU
  sta pppTransmitBuffer, x
  lda #$04
  sta pppTransmitBuffer + 1, x
  lda #$05
  sta pppTransmitBuffer + 2, x
  lda #$dc
  sta pppTransmitBuffer + 3, x
  m16
  lda pppLcpOutputCursor
  clc
  adc #$0004
  sta pppLcpOutputCursor
  m8
  bra @advanceInput

@writeAccmNak:
  assert_m8_i16
  ldx pppLcpOutputCursor
  lda #PPP_LCP_OPTION_ACCM
  sta pppTransmitBuffer, x
  lda #$06
  sta pppTransmitBuffer + 1, x
  lda #$ff
  sta pppTransmitBuffer + 2, x
  sta pppTransmitBuffer + 3, x
  sta pppTransmitBuffer + 4, x
  sta pppTransmitBuffer + 5, x
  m16
  lda pppLcpOutputCursor
  clc
  adc #$0006
  sta pppLcpOutputCursor
  m8
@advanceInput:
  assert_m8_i16
  lda pppFrameBuffer + 1, y
  sta pppLcpOptionLength
  stz pppLcpOptionLength + 1
  m16
  tya
  clc
  adc pppLcpOptionLength
  tay
  jmp @optionLoop

; Copy the rejected option exactly and leave Y at the following input option.
@copyInputOption:
  assert_m8_i16
  sty pppLcpOptionOffset
  lda pppFrameBuffer + 1, y
  sta pppLcpOptionLength
  stz pppLcpOptionLength + 1
@copyByte:
  assert_m8_i16
  ldy pppLcpOptionOffset
  ldx pppLcpOutputCursor
  lda pppFrameBuffer, y
  sta pppTransmitBuffer, x
  m16
  inc pppLcpOptionOffset
  inc pppLcpOutputCursor
  dec pppLcpOptionLength
  lda pppLcpOptionLength
  bne @copyByte16
  ldy pppLcpOptionOffset
  jmp @optionLoop
@copyByte16:
  assert_m16_i16
  m8
  bra @copyByte

@finish:
  assert_m16_i16
  lda pppLcpOutputCursor
  sec
  sbc #PPP_LCP_FRAME_OFFSET
  xba
  m8
  sta pppTransmitBuffer + 6
  xba
  sta pppTransmitBuffer + 7
  m16
  lda pppLcpOutputCursor
  ply
  plx
  plb
  rts
.endproc
