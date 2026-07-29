.include "../macro/utility.asm"
.include "constants.inc"

.code

.import pppDecoderReset, pppDecoderPush
.import pppReceiveInitialize, pppReceivePushByte
.import pppLastFrameLength, pppLastProtocol, pppFrameBuffer
.import pppFrameReady, pppReceiveLastEvent
.import pppReceiveByteCount, pppReceiveFrameCount

.export pppRunSelfTest

; Permanent on-console/QUsb2Snes regression test for the 65816 decoder.
;
; Output:
;   Carry clear, A=$00: passed
;   Carry set,   A!=0: failed step
.proc pppRunSelfTest
  .a8
  .i8

  phb
  phx
  phy
  rep #$10
  .i16

  ; Decode the fixed empty-option LCP Configure-Request from docs/ppp.md.
  setDBR .bankbyte(pppSelfTestEncoded)
  jsr pppDecoderReset
  ldx #$0000
@validLoop:
  lda pppSelfTestEncoded, x
  jsr pppDecoderPush
  cpx #(pppSelfTestEncodedEnd - pppSelfTestEncoded - 1)
  beq @validFinal
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$01
  jmp @fail
:
  inx
  bra @validLoop

@validFinal:
  cmp #PPP_EVENT_FRAME
  beq :+
  lda #$02
  jmp @fail
:

  setDBR $7e
  rep #$20
  .a16
  lda pppLastFrameLength
  cmp #$0008
  beq :+
  sep #$20
  .a8
  lda #$03
  jmp @fail
:
  .a16
  lda pppLastProtocol
  cmp #$c021
  beq :+
  sep #$20
  .a8
  lda #$04
  jmp @fail
:
  .a16
  sep #$20
  .a8

  lda pppFrameBuffer + 0
  cmp #$ff
  beq :+
  jmp @fail05
:
  lda pppFrameBuffer + 1
  cmp #$03
  beq :+
  jmp @fail05
:
  lda pppFrameBuffer + 2
  cmp #$c0
  beq :+
  jmp @fail05
:
  lda pppFrameBuffer + 3
  cmp #$21
  beq :+
  jmp @fail05
:
  lda pppFrameBuffer + 4
  cmp #$01
  beq :+
  jmp @fail05
:
  lda pppFrameBuffer + 5
  cmp #$01
  beq :+
  jmp @fail05
:
  lda pppFrameBuffer + 6
  beq :+
  jmp @fail05
:
  lda pppFrameBuffer + 7
  cmp #$04
  beq :+
  jmp @fail05
:

  ; Corrupt one Protocol octet while retaining the original FCS.
  setDBR .bankbyte(pppSelfTestEncoded)
  jsr pppDecoderReset
  ldx #$0000
@corruptLoop:
  lda pppSelfTestEncoded, x
  cpx #$0004
  bne :+
  eor #$01
:
  jsr pppDecoderPush
  cpx #(pppSelfTestEncodedEnd - pppSelfTestEncoded - 1)
  beq @corruptFinal
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$06
  jmp @fail
:
  inx
  bra @corruptLoop

@corruptFinal:
  cmp #PPP_EVENT_FCS_ERROR
  beq :+
  lda #$07
  jmp @fail
:

  ; An escape immediately followed by Flag is invalid, not an FCS error.
  jsr pppDecoderReset
  lda #PPP_FLAG_SEQUENCE
  jsr pppDecoderPush
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$08
  jmp @fail
:
  lda #$ff
  jsr pppDecoderPush
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$08
  jmp @fail
:
  lda #PPP_CONTROL_ESCAPE
  jsr pppDecoderPush
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$08
  jmp @fail
:
  lda #PPP_FLAG_SEQUENCE
  jsr pppDecoderPush
  cmp #PPP_EVENT_INVALID
  beq :+
  lda #$09
  jmp @fail
:

  ; An injected unescaped XON is removed by the default receive ACCM.
  jsr pppDecoderReset
  lda #PPP_FLAG_SEQUENCE
  jsr pppDecoderPush
  lda #$11
  jsr pppDecoderPush
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$0a
  jmp @fail
:
  ldx #$0001
@accmLoop:
  lda pppSelfTestEncoded, x
  jsr pppDecoderPush
  cpx #(pppSelfTestEncodedEnd - pppSelfTestEncoded - 1)
  beq @accmFinal
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$0a
  jmp @fail
:
  inx
  bra @accmLoop

@accmFinal:
  cmp #PPP_EVENT_FRAME
  beq :+
  lda #$0b
  jmp @fail
:

  ; Exercise the receive-owner wrapper used by the NDM24 RX drain.
  setDBR .bankbyte(pppSelfTestEncoded)
  jsr pppReceiveInitialize
  ldx #$0000
@receiveLoop:
  lda pppSelfTestEncoded, x
  jsr pppReceivePushByte
  cpx #(pppSelfTestEncodedEnd - pppSelfTestEncoded - 1)
  beq @receiveFinal
  cmp #PPP_EVENT_NONE
  beq :+
  lda #$0c
  jmp @fail
:
  inx
  bra @receiveLoop

@receiveFinal:
  cmp #PPP_EVENT_FRAME
  beq :+
  lda #$0d
  jmp @fail
:
  setDBR $7e
  lda pppFrameReady
  cmp #$01
  beq :+
  lda #$0e
  jmp @fail
:
  lda pppReceiveLastEvent
  cmp #PPP_EVENT_FRAME
  beq :+
  lda #$0f
  jmp @fail
:
  rep #$20
  .a16
  lda pppReceiveByteCount
  cmp #(pppSelfTestEncodedEnd - pppSelfTestEncoded)
  beq :+
  sep #$20
  .a8
  lda #$10
  jmp @fail
:
  .a16
  lda pppReceiveByteCount + 2
  bne @fail10_16
  lda pppReceiveFrameCount
  cmp #$0001
  bne @fail11_16
  lda pppReceiveFrameCount + 2
  bne @fail11_16
  sep #$20
  .a8

  jsr pppReceiveInitialize
  lda #$00
  clc
  bra @return

@fail10_16:
  sep #$20
  .a8
  lda #$10
  bra @fail
@fail11_16:
  sep #$20
  .a8
  lda #$11
  bra @fail
@fail05:
  lda #$05

@fail:
  pha
  jsr pppReceiveInitialize
  pla
  sec

@return:
  sep #$10
  .i8
  ply
  plx
  plb
  rts
.endproc

pppSelfTestEncoded:
  .byte $7e, $ff, $7d, $23, $c0, $21, $7d, $21, $7d
  .byte $21, $7d, $20, $7d, $24, $d1, $b5, $7e
pppSelfTestEncodedEnd:
