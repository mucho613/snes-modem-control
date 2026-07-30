.include "../macro/utility.asm"
.include "constants.inc"

.segment "BANK1_CODE"

.import pppMd5Message, pppMd5State, pppMd5Working, pppMd5Temporary
.import pppMd5Round, pppMd5WordIndex, pppMd5BlockOffset, pppMd5MessageLength

.export pppMd5Compute, pppMd5RunSelfTest

; Compute MD5 over pppMd5Message[0..pppMd5MessageLength). The input is at
; most 89 bytes in the CHAP use case, so its complete padding fits the fixed
; 128-byte private buffer. The 16-byte digest is returned in pppMd5State.
.proc pppMd5Compute
  .a8
  .i16

  phb
  phx
  phy
  setDBR $7e

  ; Append 1 bit and select the one- or two-block padded length.
  ldx pppMd5MessageLength
  lda #$80
  sta pppMd5Message, x
  inx
  lda pppMd5MessageLength + 1
  bne @twoBlocks
  lda pppMd5MessageLength
  cmp #56
  bcs @twoBlocks
  lda #$00
@zeroTo56:
  cpx #56
  beq @length
  sta pppMd5Message, x
  inx
  bra @zeroTo56
@twoBlocks:
  lda #$00
@zeroTo120:
  cpx #120
  beq @length
  sta pppMd5Message, x
  inx
  bra @zeroTo120

@length:
  ; All supported messages are shorter than 8192 bytes. Store the 64-bit
  ; little-endian bit length without a general multiplier.
  lda pppMd5MessageLength
  asl
  asl
  asl
  sta pppMd5Message, x
  lda pppMd5MessageLength
  lsr
  lsr
  lsr
  lsr
  lsr
  sta pppMd5Message + 1, x
  lda #$00
  sta pppMd5Message + 2, x
  sta pppMd5Message + 3, x
  sta pppMd5Message + 4, x
  sta pppMd5Message + 5, x
  sta pppMd5Message + 6, x
  sta pppMd5Message + 7, x

  ; RFC 1321 initial state, stored little endian.
  ldx #$000f
@copyInitial:
  lda f:pppMd5InitialState, x
  sta pppMd5State, x
  dex
  bpl @copyInitial

  stz pppMd5BlockOffset
@block:
  ldx #$000f
@copyWorking:
  lda pppMd5State, x
  sta pppMd5Working, x
  dex
  bpl @copyWorking
  stz pppMd5Round

@round:
  lda pppMd5Round
  cmp #16
  bcc @roundOne
  cmp #32
  bcc @roundTwo
  cmp #48
  bcc @roundThree

  ; F = C xor (B or not D), g = 7i mod 16.
  ldx #$0003
@fFour:
  lda pppMd5Working + 12, x
  eor #$ff
  ora pppMd5Working + 4, x
  eor pppMd5Working + 8, x
  sta pppMd5Temporary, x
  dex
  bpl @fFour
  lda pppMd5Round
  asl
  asl
  asl
  sec
  sbc pppMd5Round
  and #$0f
  bra @haveWord

@roundThree:
  ; F = B xor C xor D, g = (3i + 5) mod 16.
  ldx #$0003
@fThree:
  lda pppMd5Working + 4, x
  eor pppMd5Working + 8, x
  eor pppMd5Working + 12, x
  sta pppMd5Temporary, x
  dex
  bpl @fThree
  lda pppMd5Round
  asl
  clc
  adc pppMd5Round
  adc #5
  and #$0f
  bra @haveWord

@roundTwo:
  ; F = (D and B) or ((not D) and C), g = (5i + 1) mod 16.
  ldx #$0003
@fTwo:
  lda pppMd5Working + 12, x
  eor #$ff
  and pppMd5Working + 8, x
  sta pppMd5Temporary, x
  lda pppMd5Working + 12, x
  and pppMd5Working + 4, x
  ora pppMd5Temporary, x
  sta pppMd5Temporary, x
  dex
  bpl @fTwo
  lda pppMd5Round
  asl
  asl
  clc
  adc pppMd5Round
  adc #1
  and #$0f
  bra @haveWord

@roundOne:
  ; F = (B and C) or ((not B) and D), g = i.
  ldx #$0003
@fOne:
  lda pppMd5Working + 4, x
  eor #$ff
  and pppMd5Working + 12, x
  sta pppMd5Temporary, x
  lda pppMd5Working + 4, x
  and pppMd5Working + 8, x
  ora pppMd5Temporary, x
  sta pppMd5Temporary, x
  dex
  bpl @fOne
  lda pppMd5Round

@haveWord:
  sta pppMd5WordIndex

  ; temp += A + K[i] + M[g], all as little-endian 32-bit words.
  clc
  ldx #$0000
@addA:
  lda pppMd5Temporary, x
  adc pppMd5Working, x
  sta pppMd5Temporary, x
  php
  inx
  cpx #$0004
  beq :+
  plp_m8_i16
  bra @addA
:
  plp_m8_i16

  lda pppMd5Round
  asl
  asl
  tax
  clc
  ldy #$0000
@addK:
  lda pppMd5Temporary, y
  adc f:pppMd5RoundConstants, x
  sta pppMd5Temporary, y
  php
  inx
  iny
  cpy #$0004
  beq :+
  plp_m8_i16
  bra @addK
:
  plp_m8_i16

  lda pppMd5WordIndex
  asl
  asl
  clc
  adc pppMd5BlockOffset
  tax
  clc
  ldy #$0000
@addMessage:
  lda pppMd5Temporary, y
  adc pppMd5Message, x
  sta pppMd5Temporary, y
  php
  inx
  iny
  cpy #$0004
  beq :+
  plp_m8_i16
  bra @addMessage
:
  plp_m8_i16

  ; Rotate the complete 32-bit word left by the per-round amount.
  ldx #$0000
  lda pppMd5Round
  tax
  lda f:pppMd5ShiftAmounts, x
  sta pppMd5WordIndex
@rotate:
  asl pppMd5Temporary
  rol pppMd5Temporary + 1
  rol pppMd5Temporary + 2
  rol pppMd5Temporary + 3
  bcc :+
  inc pppMd5Temporary
:
  dec pppMd5WordIndex
  bne @rotate

  ; temp += B.
  clc
  ldx #$0000
@addB:
  lda pppMd5Temporary, x
  adc pppMd5Working + 4, x
  sta pppMd5Temporary, x
  php
  inx
  cpx #$0004
  beq :+
  plp_m8_i16
  bra @addB
:
  plp_m8_i16

  ; A=D; D=C; C=B; B=temp.
  ldx #$0003
@shuffle:
  lda pppMd5Working + 12, x
  sta pppMd5Working, x
  lda pppMd5Working + 8, x
  sta pppMd5Working + 12, x
  lda pppMd5Working + 4, x
  sta pppMd5Working + 8, x
  lda pppMd5Temporary, x
  sta pppMd5Working + 4, x
  dex
  bpl @shuffle

  inc pppMd5Round
  lda pppMd5Round
  cmp #64
  beq :+
  jmp @round
:

  ; Add this block's working state back into the accumulated state.
  ldy #$0000
@stateWord:
  clc
  ldx #$0000
@stateByte:
  lda pppMd5State, y
  adc pppMd5Working, y
  sta pppMd5State, y
  php
  iny
  inx
  cpx #$0004
  beq :+
  plp_m8_i16
  bra @stateByte
:
  plp_m8_i16
  cpy #$0010
  bne @stateWord

  lda pppMd5BlockOffset
  bne @done
  lda pppMd5MessageLength
  cmp #56
  bcc @done
  lda #64
  sta pppMd5BlockOffset
  jmp @block

@done:
  ply
  plx
  plb
  rtl
.endproc

; Closed fixture for the canonical MD5("abc") vector.
.proc pppMd5RunSelfTest
  .a8
  .i16

  phb
  phx
  setDBR $7e
  lda #'a'
  sta pppMd5Message
  lda #'b'
  sta pppMd5Message + 1
  lda #'c'
  sta pppMd5Message + 2
  m16
  lda #3
  sta pppMd5MessageLength
  m8
  jsl pppMd5Compute
  ldx #$0000
@compare:
  lda pppMd5State, x
  cmp f:pppMd5AbcDigest, x
  bne @failed
  inx
  cpx #$0010
  bne @compare
  lda #$00
  plx
  plb
  clc
  rtl
@failed:
  lda #$8a
  plx
  plb
  sec
  rtl
.endproc

.segment "DATA"

pppMd5InitialState:
  .byte $01, $23, $45, $67, $89, $ab, $cd, $ef
  .byte $fe, $dc, $ba, $98, $76, $54, $32, $10

pppMd5AbcDigest:
  .byte $90, $01, $50, $98, $3c, $d2, $4f, $b0
  .byte $d6, $96, $3f, $7d, $28, $e1, $7f, $72

pppMd5ShiftAmounts:
  .byte 7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22
  .byte 5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20
  .byte 4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23
  .byte 6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21

pppMd5RoundConstants:
  .dword $d76aa478, $e8c7b756, $242070db, $c1bdceee
  .dword $f57c0faf, $4787c62a, $a8304613, $fd469501
  .dword $698098d8, $8b44f7af, $ffff5bb1, $895cd7be
  .dword $6b901122, $fd987193, $a679438e, $49b40821
  .dword $f61e2562, $c040b340, $265e5a51, $e9b6c7aa
  .dword $d62f105d, $02441453, $d8a1e681, $e7d3fbc8
  .dword $21e1cde6, $c33707d6, $f4d50d87, $455a14ed
  .dword $a9e3e905, $fcefa3f8, $676f02d9, $8d2a4c8a
  .dword $fffa3942, $8771f681, $6d9d6122, $fde5380c
  .dword $a4beea44, $4bdecfa9, $f6bb4b60, $bebfbc70
  .dword $289b7ec6, $eaa127fa, $d4ef3085, $04881d05
  .dword $d9d4d039, $e6db99e5, $1fa27cf8, $c4ac5665
  .dword $f4292244, $432aff97, $ab9423a7, $fc93a039
  .dword $655b59c3, $8f0ccc92, $ffeff47d, $85845dd1
  .dword $6fa87e4f, $fe2ce6e0, $a3014314, $4e0811a1
  .dword $f7537e82, $bd3af235, $2ad7d2bb, $eb86d391
