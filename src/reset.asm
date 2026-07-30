.import initializeRegisters
.import clearBG1Tile
.import copyPalette
.import copyPattern
.import VBlank
.import clearRamAll
.import readController1
.import terminalInitialize
.import statusInitialize, statusPoll
.import clockInitialize, clockPoll
.import modemInitializeDiagnostics
.import modemInitialize
.import modemPoll, modemSessionPoll, modemMailboxPoll
.import modemSpeedTestInitialize, modemSpeedTestPoll
.import pppDiagnosticInitialize
.import pppReceiveInitialize, pppReceivePoll
.import pppTransmitInitialize, pppTransmitPoll
.import pppLcpInitialize
.import pppLcpPoll
.import pppPapInitialize, pppPapPoll
.import pppPapCredentialsInitialize
.import pppChapInitialize, pppChapPoll
.import pppIpcpInitialize, pppIpcpPoll
.import pppIpv4Initialize, pppIpv4Poll
.import pppIcmpInitialize
.import pppIcmpRequestPoll
.import pppUdpInitialize
.import pppNtpInitialize, pppNtpPoll
.import pppDnsInitialize, pppDnsPoll
.import nmitimenShadow

.include "./registers.inc"
.include "./macro/utility.asm"
.include "./modem/generated.inc"
.include "./ram/clearAll.inc"

.code

.export EmptyInt
.proc EmptyInt
  interrupt_entry
@infiniteLoop:
  jmp @infiniteLoop
.endproc

.export Reset
.proc Reset
  .a8
  .i8
  jml ResetFast
.endproc

.proc ResetFast
  .a8
  .i8
  enterNativeM8I16

  ldx #$1fff
  txs
  setDP $0000

  m16
  clearRamAll
  jsl initializeRegisters

  m16
  jsl clearBG1Tile
  jsl copyPalette
  jsl copyPattern
  jsr terminalInitialize
  jsr clockInitialize

  mi8
  jsr modemInitializeDiagnostics
  jsr modemSpeedTestInitialize
  i16
  jsr pppDiagnosticInitialize
  jsr pppReceiveInitialize
  jsr pppTransmitInitialize
  jsr pppLcpInitialize
  jsr pppPapInitialize
  jsl pppPapCredentialsInitialize
  jsl pppChapInitialize
  jsr pppIpcpInitialize
  jsr pppIpv4Initialize
  jsr pppIcmpInitialize
  jsr pppUdpInitialize
  jsr pppNtpInitialize
  jsr pppDnsInitialize

  mi16
  jsl statusInitialize
  i8
  ; The status screen is the default; the font specimen intentionally starts
  ; on the raw terminal tilemap.
  .ifdef MODEM_FONT_TEST
    lda #TERMINAL_BG1SC
  .else
    lda #TERMINAL_STATUS_BG1SC
  .endif
  sta BG1SC
  lda #$01
  sta TM
  stz TS
  lda #$0f
  sta INIDISP

  mi16
  .ifdef MODEM_SMOKE_TEST
    jsr modemInitialize
  .endif

  mi8
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
    mi16
    jsr readController1
    jsr modemMailboxPoll
    jsr modemPoll
    jsr modemSpeedTestPoll
    jsr modemSessionPoll
    jsr pppReceivePoll
    jsr pppLcpPoll
    jsr pppPapPoll
    jsl pppChapPoll
    jsr pppIpcpPoll
    jsr pppIpv4Poll
    jsr pppIcmpRequestPoll
    jsr pppNtpPoll
    jsr pppDnsPoll
    jsr clockPoll
    jsl statusPoll
    jsr pppTransmitPoll
  .endif
  bra @mainLoop
.endproc
