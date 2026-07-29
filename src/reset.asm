.import initializeRegisters
.import transferText
.import bg1YScrollPos
.import clearBG1Tile
.import setBG1Tile
.import copyPalette
.import copyPattern
.import VBlank
.import clearRamAll
.import readController1
.import modemInitializeDiagnostics
.import modemInitialize, modemPoll, modemSessionPoll, modemMailboxPoll
.import bufW12SEL
.import bufWH0
.import bufWH1

.include "./registers.inc"
.include "./macro/utility.asm"
.include "./ram/clearAll.inc"

.code

.export EmptyInt
.proc EmptyInt
@infiniteLoop:
  jmp @infiniteLoop
.endproc

.export Reset
.proc Reset
  jml ResetFast
.endproc

.proc ResetFast
  clc
  xce

  rep #$ff
  sep #$24
  .a8
  .i16

  ldx #$1fff
  txs
  setDP $0000

  rep #$20
  .a16
  clearRamAll
  jsr initializeRegisters

  rep #$20
  .a16
  jsr clearBG1Tile
  jsr setBG1Tile
  jsr copyPalette
  jsr copyPattern

  sep #$30
  .a8
  .i8
  jsr modemInitializeDiagnostics

  lda #$fa
  sta BG1SC
  lda #$01
  sta TM
  sta TS
  lda #$0f
  sta INIDISP

  rep #$30
  .a16
  .i16
  lda #$01ff
  sta bg1YScrollPos

  .ifdef MODEM_SMOKE_TEST
    jsr modemInitialize
  .endif

  sep #$30
  .a8
  .i8

  ; NMI enabled, automatic joypad reading disabled.
  lda #$80
  sta NMITIMEN
  cli

  lda #$03
  sta W12SEL
  lda #$18
  sta WH0
  lda #$e4
  sta WH1
  lda #$01
  sta TMW
  sta TSW

@mainLoop:
  rep #$30
  .a16
  .i16
  jsr readController1
  jsr modemMailboxPoll
  jsr modemPoll
  jsr modemSessionPoll
  bra @mainLoop
.endproc
