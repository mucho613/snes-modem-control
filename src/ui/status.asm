.include "../registers.inc"
.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "../ppp/constants.inc"

SCREEN_MODE_STATUS = $00
SCREEN_MODE_RAW_LOG = $01

STATUS_PAGE_COMMON = $00
STATUS_PAGE_NTP = $01
STATUS_PAGE_DNS = $02
STATUS_PAGE_ICMP = $03
STATUS_PAGE_COUNT = $04

CONTROLLER_BUTTON_L = $0020
CONTROLLER_BUTTON_R = $0010
CONTROLLER_BUTTON_LEFT = $0200
CONTROLLER_BUTTON_RIGHT = $0100

STATUS_VALUE_COLUMN = 7

.assert TERMINAL_COLUMNS = 32, error, "status renderer requires 32 columns"
.assert TERMINAL_STATUS_ROWS = 32, error, "status renderer requires 32 rows"

.macro statusWriteImmediate row, column, text
  .repeat .strlen(text), index
    lda #.strat(text, index)
    sta statusTileBuffer + (row * TERMINAL_COLUMNS) + column + index
  .endrepeat
.endmacro

.macro statusClearValue row
  ldx #(row * TERMINAL_COLUMNS) + STATUS_VALUE_COLUMN
  lda #' '
:
  sta statusTileBuffer, x
  inx
  cpx #((row + 1) * TERMINAL_COLUMNS)
  bne :-
.endmacro

.macro statusJumpIfEqual target
  bne :+
  jmp target
:
.endmacro

.segment "BANK1_CODE"

.import frameCounter
.import controller1Input, controller1InputPulse
.import modemDriverState
.import pppLcpState, pppPapState, pppIpcpState
.import pppIpcpFlags, pppIpcpLocalAddress, pppIpcpPeerAddress
.import terminalVerticalScroll
.import screenMode, statusPage, statusRenderedPage, statusDirectionLatch
.import statusTileBuffer, statusRenderRow, statusLastUpdateFrame
.import applicationStatusInitialize, applicationStatusPoll

.export statusInitialize, statusPoll
.export statusRenderVBlank, screenApplyVBlank

; Initialize the status model while the PPU is forced blank. The common UI
; owns page zero; the build-time application adapter owns protocol pages.
.proc statusInitialize
  .a16
  .i16

  pha
  phb
  phd
  phx
  phy

  setDBR $7e
  m8
  ldx #$0000
  lda #' '
@clearTileBuffer:
  sta statusTileBuffer, x
  inx
  cpx #(TERMINAL_COLUMNS * TERMINAL_STATUS_ROWS)
  bne @clearTileBuffer

  stz statusPage
  stz statusDirectionLatch
  lda #$ff
  sta statusRenderedPage
  stz statusRenderRow
  sta statusLastUpdateFrame
  sta statusLastUpdateFrame + 1

  .ifdef MODEM_FONT_TEST
    lda #SCREEN_MODE_RAW_LOG
  .else
    lda #SCREEN_MODE_STATUS
  .endif
  sta screenMode

  jsr statusUpdateBuffer

  ; Populate the complete status tilemap immediately. Subsequent frames
  ; refresh one row at a time during VBlank.
  setDP $2100
  m16
  lda #TERMINAL_STATUS_TILEMAP_BASE
  sta .lobyte(VMADDL)
  m8
  ldx #$0000
@copyInitial:
  lda statusTileBuffer, x
  sta .lobyte(VMDATAL)
  stz .lobyte(VMDATAH)
  inx
  cpx #(TERMINAL_COLUMNS * TERMINAL_STATUS_ROWS)
  bne @copyInitial

  m16
  ply
  plx
  pld
  plb
  pla
  rtl
.endproc

; Clear and label a newly selected page. This happens in the main loop, never
; in VBlank, so page adapters remain independent from PPU timing.
.proc statusPreparePage
  .a8
  .i16

  ldx #$0000
  lda #' '
@clear:
  sta statusTileBuffer, x
  inx
  cpx #(TERMINAL_COLUMNS * TERMINAL_STATUS_ROWS)
  bne @clear

  lda statusPage
  sta statusRenderedPage
  beq :+
  jmp @application
:

  statusWriteImmediate 0, 0, "MODEM  "
  statusWriteImmediate 1, 0, "LCP    "
  statusWriteImmediate 2, 0, "PAP    "
  statusWriteImmediate 3, 0, "IPCP   "
  statusWriteImmediate 4, 0, "LOCAL  "
  statusWriteImmediate 5, 0, "PEER   "
  rts

@application:
  jsl applicationStatusInitialize
  rts
.endproc

; Rebuild the selected human-facing page once per frame.
.proc statusUpdateBuffer
  .a8
  .i16

  lda statusPage
  cmp statusRenderedPage
  beq :+
  jsr statusPreparePage
:
  lda statusPage
  beq @common
  jsl applicationStatusPoll
  rts

@common:
  statusClearValue 0
  lda modemDriverState
  cmp #MODEM_STATE_RESETTING
  statusJumpIfEqual @modemResetting
  cmp #MODEM_STATE_PROBING
  statusJumpIfEqual @modemProbing
  cmp #MODEM_STATE_READY
  statusJumpIfEqual @modemReady
  cmp #MODEM_STATE_AT_COMMAND
  statusJumpIfEqual @modemAt
  cmp #MODEM_STATE_DIALING
  statusJumpIfEqual @modemDialing
  cmp #MODEM_STATE_CONNECTED
  statusJumpIfEqual @modemConnected
  cmp #MODEM_STATE_DISCONNECTING
  statusJumpIfEqual @modemDisconnecting
  cmp #MODEM_STATE_ERROR
  statusJumpIfEqual @modemError
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "OFF"
  jmp @modemDone
@modemResetting:
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "RESETTING"
  jmp @modemDone
@modemProbing:
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "PROBING"
  jmp @modemDone
@modemReady:
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "READY"
  jmp @modemDone
@modemAt:
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "AT COMMAND"
  jmp @modemDone
@modemDialing:
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "DIALING"
  jmp @modemDone
@modemConnected:
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "CONNECTED"
  jmp @modemDone
@modemDisconnecting:
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "DISCONNECTING"
  jmp @modemDone
@modemError:
  statusWriteImmediate 0, STATUS_VALUE_COLUMN, "ERROR"
@modemDone:

  statusClearValue 1
  lda pppLcpState
  jsr @writePppState

  statusClearValue 2
  lda pppPapState
  cmp #PPP_PAP_STATE_OPENED
  statusJumpIfEqual @papOpen
  cmp #PPP_PAP_STATE_WAITING_FOR_REPLY
  statusJumpIfEqual @papNegotiating
  cmp #PPP_PAP_STATE_REQUEST_PENDING
  statusJumpIfEqual @papNegotiating
  cmp #PPP_PAP_STATE_FAILED
  statusJumpIfEqual @papFailed
  statusWriteImmediate 2, STATUS_VALUE_COLUMN, "INACTIVE"
  jmp @papDone
@papOpen:
  statusWriteImmediate 2, STATUS_VALUE_COLUMN, "OPEN"
  jmp @papDone
@papNegotiating:
  statusWriteImmediate 2, STATUS_VALUE_COLUMN, "NEGOTIATING"
  jmp @papDone
@papFailed:
  statusWriteImmediate 2, STATUS_VALUE_COLUMN, "FAILED"
@papDone:

  statusClearValue 3
  lda pppIpcpState
  jsr @writePppState

  statusClearValue 4
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_LOCAL_VALID
  beq @localUnavailable
  ldx #(4 * TERMINAL_COLUMNS) + STATUS_VALUE_COLUMN
  ldy #.loword(pppIpcpLocalAddress)
  jsr @writeIpv4
  bra @localDone
@localUnavailable:
  statusWriteImmediate 4, STATUS_VALUE_COLUMN, "---.---.---.---"
@localDone:

  statusClearValue 5
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_PEER_VALID
  beq @peerUnavailable
  ldx #(5 * TERMINAL_COLUMNS) + STATUS_VALUE_COLUMN
  ldy #.loword(pppIpcpPeerAddress)
  jsr @writeIpv4
  bra @peerDone
@peerUnavailable:
  statusWriteImmediate 5, STATUS_VALUE_COLUMN, "---.---.---.---"
@peerDone:
  rts

; A contains an RFC 1661-style state. X points one byte past the cleared row.
@writePppState:
  cmp #PPP_LCP_STATE_OPENED
  statusJumpIfEqual @pppOpen
  cmp #PPP_LCP_STATE_REQUEST_SENT
  statusJumpIfEqual @pppNegotiating
  cmp #PPP_LCP_STATE_ACK_RECEIVED
  statusJumpIfEqual @pppNegotiating
  cmp #PPP_LCP_STATE_ACK_SENT
  statusJumpIfEqual @pppNegotiating
  cmp #PPP_LCP_STATE_STOPPED
  statusJumpIfEqual @pppStopped
  cpx #(2 * TERMINAL_COLUMNS)
  beq @pppClosedLcp
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "CLOSED"
  rts
@pppClosedLcp:
  statusWriteImmediate 1, STATUS_VALUE_COLUMN, "CLOSED"
  rts
@pppOpen:
  cpx #(2 * TERMINAL_COLUMNS)
  beq @pppOpenLcp
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "OPEN"
  rts
@pppOpenLcp:
  statusWriteImmediate 1, STATUS_VALUE_COLUMN, "OPEN"
  rts
@pppNegotiating:
  cpx #(2 * TERMINAL_COLUMNS)
  beq @pppNegotiatingLcp
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "NEGOTIATING"
  rts
@pppNegotiatingLcp:
  statusWriteImmediate 1, STATUS_VALUE_COLUMN, "NEGOTIATING"
  rts
@pppStopped:
  cpx #(2 * TERMINAL_COLUMNS)
  beq @pppStoppedLcp
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "STOPPED"
  rts
@pppStoppedLcp:
  statusWriteImmediate 1, STATUS_VALUE_COLUMN, "STOPPED"
  rts

; Write the four network-order bytes at WRAM Y as unpadded decimal text.
@writeIpv4:
  lda $0000, y
  jsr @writeDecimal
  lda #'.'
  sta statusTileBuffer, x
  inx
  iny
  lda $0000, y
  jsr @writeDecimal
  lda #'.'
  sta statusTileBuffer, x
  inx
  iny
  lda $0000, y
  jsr @writeDecimal
  lda #'.'
  sta statusTileBuffer, x
  inx
  iny
  lda $0000, y
  jsr @writeDecimal
  rts

@writeDecimal:
  phy
  cmp #200
  bcc @lessThanTwoHundred
  sec
  sbc #200
  pha
  lda #'2'
  sta statusTileBuffer, x
  inx
  pla
  bra @writeRequiredTens
@lessThanTwoHundred:
  cmp #100
  bcc @writeOptionalTens
  sec
  sbc #100
  pha
  lda #'1'
  sta statusTileBuffer, x
  inx
  pla
@writeRequiredTens:
  ldy #'0'
@requiredTensLoop:
  cmp #10
  bcc @requiredTensDone
  sec
  sbc #10
  iny
  bra @requiredTensLoop
@requiredTensDone:
  pha
  tya
  sta statusTileBuffer, x
  inx
  pla
  bra @writeOnes
@writeOptionalTens:
  cmp #10
  bcc @writeOnes
  ldy #'0'
@optionalTensLoop:
  cmp #10
  bcc @optionalTensDone
  sec
  sbc #10
  iny
  bra @optionalTensLoop
@optionalTensDone:
  pha
  tya
  sta statusTileBuffer, x
  inx
  pla
@writeOnes:
  clc
  adc #'0'
  sta statusTileBuffer, x
  inx
  ply
  rts
.endproc

; Status mode: D-pad changes pages and R opens raw log.
; Raw-log mode: only L returns to the last selected status page.
.proc statusPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e

  m8
  lda screenMode
  cmp #SCREEN_MODE_RAW_LOG
  bne @statusInput

  m16
  lda controller1InputPulse
  and #CONTROLLER_BUTTON_L
  beq @update
  m8
  stz screenMode
  bra @update

@statusInput:
  m16
  lda controller1InputPulse
  and #CONTROLLER_BUTTON_R
  beq @direction
  m8
  lda #SCREEN_MODE_RAW_LOG
  sta screenMode
  bra @update

@direction:
  m16
  lda controller1Input
  and #(CONTROLLER_BUTTON_LEFT | CONTROLLER_BUTTON_RIGHT)
  bne @directionPressed
  m8
  stz statusDirectionLatch
  bra @update

@directionPressed:
  m8
  lda statusDirectionLatch
  bne @update
  inc statusDirectionLatch

  m16
  lda controller1Input
  and #CONTROLLER_BUTTON_LEFT
  beq @right
  m8
  lda statusPage
  bne :+
  lda #STATUS_PAGE_COUNT
:
  dec
  sta statusPage
  bra @update

@right:
  m16
  lda controller1Input
  and #CONTROLLER_BUTTON_RIGHT
  beq @update
  m8
  inc statusPage
  lda statusPage
  cmp #STATUS_PAGE_COUNT
  bcc @update
  stz statusPage

@update:
  m16
  lda frameCounter
  cmp statusLastUpdateFrame
  beq @done
  sta statusLastUpdateFrame
  m8
  jsr statusUpdateBuffer

@done:
  m16
  ply
  plx
  plb
  pla
  rtl
.endproc

; Copy one status row per VBlank. This bounded refresh makes protocol and
; clock formatting independent from the PPU timing budget.
.proc statusRenderVBlank
  .a8
  .i16

  php
  i16
  pha
  phb
  phd
  phx
  phy
  setDBR $7e
  setDP $2100

  m16
  lda statusRenderRow
  and #$00ff
  asl
  asl
  asl
  asl
  asl
  tax
  clc
  adc #TERMINAL_STATUS_TILEMAP_BASE
  sta .lobyte(VMADDL)

  m8
  ldy #TERMINAL_COLUMNS
@copyRow:
  lda statusTileBuffer, x
  sta .lobyte(VMDATAL)
  stz .lobyte(VMDATAH)
  inx
  dey
  bne @copyRow

  inc statusRenderRow
  lda statusRenderRow
  and #(TERMINAL_STATUS_ROWS - 1)
  sta statusRenderRow

  ply
  plx
  pld
  plb
  pla
  plp
  rtl
.endproc

; Select the visible tilemap without disturbing either screen's state.
.proc screenApplyVBlank
  .a8
  .i16

  pha
  phb
  phd
  setDBR $7e
  setDP $2100

  lda screenMode
  cmp #SCREEN_MODE_RAW_LOG
  beq @raw

  lda #TERMINAL_STATUS_BG1SC
  sta .lobyte(BG1SC)
  ; A vertical offset of zero clips the top scanline on the SFC. Write -1
  ; through the BG scroll latch so status row zero is visible in full.
  lda #$ff
  sta .lobyte(BG1VOFS)
  sta .lobyte(BG1VOFS)
  bra @done

@raw:
  lda #TERMINAL_BG1SC
  sta .lobyte(BG1SC)
  lda terminalVerticalScroll
  sta .lobyte(BG1VOFS)
  lda terminalVerticalScroll + 1
  sta .lobyte(BG1VOFS)

@done:
  pld
  plb
  pla
  rtl
.endproc
