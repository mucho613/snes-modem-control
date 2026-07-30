.import initializeRegisters
.import clearBG1Tile
.import copyPalette
.import copyPattern
.import VBlank
.import clearRamAll
.import readController1
.import terminalInitialize
.import modemInitializeDiagnostics
.import modemInitialize
.import modemPoll, modemSessionPoll, modemMailboxPoll
.import pppDiagnosticInitialize
.import pppReceiveInitialize, pppReceivePoll
.import pppTransmitInitialize, pppTransmitPoll
.import pppLcpInitialize
.import pppLcpPoll
.import pppPapInitialize, pppPapPoll
.import pppIpcpInitialize, pppIpcpPoll
.import pppIpv4Initialize, pppIpv4Poll
.import pppIcmpInitialize
.import pppUdpInitialize
.import pppNtpInitialize, pppNtpPoll
.import nmitimenShadow

.include "./registers.inc"
.include "./macro/utility.asm"
.include "./modem/generated.inc"
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
  jsr copyPalette
  jsr copyPattern
  jsr terminalInitialize

  sep #$30
  .a8
  .i8
  jsr modemInitializeDiagnostics
  rep #$10
  .i16
  jsr pppDiagnosticInitialize
  jsr pppReceiveInitialize
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
  jsr pppPapInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppIcmpInitialize
  jsr pppUdpInitialize
  jsr pppNtpInitialize
  sep #$10
  .i8

  ; BG1 tilemap at VRAM $4000, 32x64 tiles.
  lda #TERMINAL_BG1SC
  sta BG1SC
  lda #$01
  sta TM
  stz TS
  lda #$0f
  sta INIDISP

  rep #$30
  .a16
  .i16
  .ifdef MODEM_SMOKE_TEST
    jsr modemInitialize
  .endif

  sep #$30
  .a8
  .i8

  ; NMI enabled, automatic joypad reading disabled.
  lda #$80
  phb
  setDBR $7e
  sta nmitimenShadow
  plb
  sta NMITIMEN
  cli

@mainLoop:
  .ifdef MODEM_FONT_TEST
    ; The font specimen is a static display test. Leave controller-port and
    ; NDM24 activity disabled while NMI continues rendering the display queue.
    wai
  .else
    rep #$30
    .a16
    .i16
    jsr readController1
    jsr modemMailboxPoll
    jsr modemPoll
    jsr modemSessionPoll
    jsr pppReceivePoll
    jsr pppLcpPoll
    jsr pppPapPoll
    jsr pppIpcpPoll
    jsr pppIpv4Poll
    jsr pppNtpPoll
    jsr pppTransmitPoll
  .endif
  bra @mainLoop
.endproc
