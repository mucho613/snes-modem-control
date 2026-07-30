.include "../registers.inc"
.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "../ppp/constants.inc"

SCREEN_MODE_STATUS = $00
SCREEN_MODE_RAW_LOG = $01

CONTROLLER_BUTTON_L = $20
CONTROLLER_BUTTON_R = $10

STATUS_VALUE_COLUMN = 7
STATUS_VALUE_WIDTH = TERMINAL_COLUMNS - STATUS_VALUE_COLUMN

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

.code

.import frameCounter
.import controller1InputPulse
.import modemDriverState
.import pppLcpState, pppPapState, pppIpcpState
.import pppIpcpFlags, pppIpcpLocalAddress, pppIpcpPeerAddress
.import terminalVerticalScroll
.import screenMode
.import statusTileBuffer, statusRenderRow, statusLastUpdateFrame
.import statusApplicationName, statusApplicationState, statusApplicationValue
.import applicationStatusInitialize, applicationStatusPoll

.export statusInitialize, statusPoll
.export statusRenderVBlank, screenApplyVBlank

; Initialize the generic status model and its fixed shell while the PPU is
; forced blank. Application-specific rows are supplied by the selected
; adapter through three fixed-width buffers.
.proc statusInitialize
  .a16
  .i16

  pha
  phb
  phd
  phx
  phy

  setDBR $7e
  sep #$20
  .a8

  ldx #$0000
  lda #' '
@clearTileBuffer:
  sta statusTileBuffer, x
  inx
  cpx #(TERMINAL_COLUMNS * TERMINAL_STATUS_ROWS)
  bne @clearTileBuffer

  ldx #$0000
@clearApplicationBuffers:
  sta statusApplicationName, x
  sta statusApplicationState, x
  sta statusApplicationValue, x
  inx
  cpx #STATUS_VALUE_WIDTH
  bne @clearApplicationBuffers

  stz statusRenderRow
  lda #$ff
  sta statusLastUpdateFrame
  sta statusLastUpdateFrame + 1

  .ifdef MODEM_FONT_TEST
    lda #SCREEN_MODE_RAW_LOG
  .else
    lda #SCREEN_MODE_STATUS
  .endif
  sta screenMode

  statusWriteImmediate 0, 0, "modem-control-test"
  statusWriteImmediate 1, 0, "--------------------------------"
  statusWriteImmediate 3, 0, "MODEM  "
  statusWriteImmediate 4, 0, "LCP    "
  statusWriteImmediate 5, 0, "PAP    "
  statusWriteImmediate 6, 0, "IPCP   "
  statusWriteImmediate 7, 0, "LOCAL  "
  statusWriteImmediate 8, 0, "PEER   "
  statusWriteImmediate 10, 0, "APP    "
  statusWriteImmediate 11, 0, "STATE  "
  statusWriteImmediate 12, 0, "TIME   "

  jsr applicationStatusInitialize
  jsr statusUpdateBuffer

  ; Populate the complete status tilemap immediately. Subsequent frames
  ; refresh one row at a time during VBlank.
  setDP $2100
  rep #$20
  .a16
  lda #TERMINAL_STATUS_TILEMAP_BASE
  sta .lobyte(VMADDL)
  sep #$20
  .a8
  ldx #$0000
@copyInitial:
  lda statusTileBuffer, x
  sta .lobyte(VMDATAL)
  stz .lobyte(VMDATAH)
  inx
  cpx #(TERMINAL_COLUMNS * TERMINAL_STATUS_ROWS)
  bne @copyInitial

  rep #$20
  .a16
  ply
  plx
  pld
  plb
  pla
  rts
.endproc

; Rebuild human-facing values. This routine and the application adapter run
; only in the main loop; VBlank merely copies the resulting character rows.
.proc statusUpdateBuffer
  .a8
  .i16

  jsr applicationStatusPoll

  statusClearValue 3
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
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "OFF"
  jmp @modemDone
@modemResetting:
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "RESETTING"
  jmp @modemDone
@modemProbing:
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "PROBING"
  jmp @modemDone
@modemReady:
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "READY"
  jmp @modemDone
@modemAt:
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "AT COMMAND"
  jmp @modemDone
@modemDialing:
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "DIALING"
  jmp @modemDone
@modemConnected:
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "CONNECTED"
  jmp @modemDone
@modemDisconnecting:
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "DISCONNECTING"
  jmp @modemDone
@modemError:
  statusWriteImmediate 3, STATUS_VALUE_COLUMN, "ERROR"
@modemDone:

  statusClearValue 4
  lda pppLcpState
  jsr @writePppState

  statusClearValue 5
  lda pppPapState
  cmp #PPP_PAP_STATE_OPENED
  statusJumpIfEqual @papOpen
  cmp #PPP_PAP_STATE_WAITING_FOR_REPLY
  statusJumpIfEqual @papNegotiating
  cmp #PPP_PAP_STATE_REQUEST_PENDING
  statusJumpIfEqual @papNegotiating
  cmp #PPP_PAP_STATE_FAILED
  statusJumpIfEqual @papFailed
  statusWriteImmediate 5, STATUS_VALUE_COLUMN, "INACTIVE"
  jmp @papDone
@papOpen:
  statusWriteImmediate 5, STATUS_VALUE_COLUMN, "OPEN"
  jmp @papDone
@papNegotiating:
  statusWriteImmediate 5, STATUS_VALUE_COLUMN, "NEGOTIATING"
  jmp @papDone
@papFailed:
  statusWriteImmediate 5, STATUS_VALUE_COLUMN, "FAILED"
@papDone:

  statusClearValue 6
  lda pppIpcpState
  jsr @writePppState

  statusClearValue 7
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_LOCAL_VALID
  beq @localUnavailable
  ldx #(7 * TERMINAL_COLUMNS) + STATUS_VALUE_COLUMN
  ldy #.loword(pppIpcpLocalAddress)
  jsr @writeIpv4
  bra @localDone
@localUnavailable:
  statusWriteImmediate 7, STATUS_VALUE_COLUMN, "---.---.---.---"
@localDone:

  statusClearValue 8
  lda pppIpcpFlags
  and #PPP_IPCP_FLAG_PEER_VALID
  beq @peerUnavailable
  ldx #(8 * TERMINAL_COLUMNS) + STATUS_VALUE_COLUMN
  ldy #.loword(pppIpcpPeerAddress)
  jsr @writeIpv4
  bra @peerDone
@peerUnavailable:
  statusWriteImmediate 8, STATUS_VALUE_COLUMN, "---.---.---.---"
@peerDone:

  statusClearValue 10
  statusClearValue 11
  statusClearValue 12
  ldx #$0000
@copyApplication:
  lda statusApplicationName, x
  sta statusTileBuffer + (10 * TERMINAL_COLUMNS) + STATUS_VALUE_COLUMN, x
  lda statusApplicationState, x
  sta statusTileBuffer + (11 * TERMINAL_COLUMNS) + STATUS_VALUE_COLUMN, x
  lda statusApplicationValue, x
  sta statusTileBuffer + (12 * TERMINAL_COLUMNS) + STATUS_VALUE_COLUMN, x
  inx
  cpx #STATUS_VALUE_WIDTH
  bne @copyApplication
  rts

; A contains an RFC 1661-style state, and the destination row has already
; been selected by the caller's immediately preceding statusClearValue.
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
  ; The caller is either the LCP row (4) or IPCP row (6). X still points one
  ; byte past that row because statusClearValue leaves it at the row end.
  cpx #(5 * TERMINAL_COLUMNS)
  beq @pppClosedLcp
  statusWriteImmediate 6, STATUS_VALUE_COLUMN, "CLOSED"
  rts
@pppClosedLcp:
  statusWriteImmediate 4, STATUS_VALUE_COLUMN, "CLOSED"
  rts
@pppOpen:
  cpx #(5 * TERMINAL_COLUMNS)
  beq @pppOpenLcp
  statusWriteImmediate 6, STATUS_VALUE_COLUMN, "OPEN"
  rts
@pppOpenLcp:
  statusWriteImmediate 4, STATUS_VALUE_COLUMN, "OPEN"
  rts
@pppNegotiating:
  cpx #(5 * TERMINAL_COLUMNS)
  beq @pppNegotiatingLcp
  statusWriteImmediate 6, STATUS_VALUE_COLUMN, "NEGOTIATING"
  rts
@pppNegotiatingLcp:
  statusWriteImmediate 4, STATUS_VALUE_COLUMN, "NEGOTIATING"
  rts
@pppStopped:
  cpx #(5 * TERMINAL_COLUMNS)
  beq @pppStoppedLcp
  statusWriteImmediate 6, STATUS_VALUE_COLUMN, "STOPPED"
  rts
@pppStoppedLcp:
  statusWriteImmediate 4, STATUS_VALUE_COLUMN, "STOPPED"
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

; Handle edge-triggered L/R selection and rebuild status data once per frame.
.proc statusPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e

  sep #$20
  .a8
  lda controller1InputPulse
  and #CONTROLLER_BUTTON_L
  beq :+
  stz screenMode
:
  lda controller1InputPulse
  and #CONTROLLER_BUTTON_R
  beq :+
  lda #SCREEN_MODE_RAW_LOG
  sta screenMode
:

  rep #$20
  .a16
  lda frameCounter
  cmp statusLastUpdateFrame
  beq @done
  sta statusLastUpdateFrame
  sep #$20
  .a8
  jsr statusUpdateBuffer

@done:
  rep #$20
  .a16
  ply
  plx
  plb
  pla
  rts
.endproc

; Copy one status row per VBlank. This bounded refresh makes protocol and
; clock formatting independent from the PPU timing budget.
.proc statusRenderVBlank
  .a8
  .i16

  php
  rep #$10
  .i16
  pha
  phb
  phd
  phx
  phy
  setDBR $7e
  setDP $2100

  rep #$20
  .a16
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

  sep #$20
  .a8
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
  rts
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
  stz .lobyte(BG1VOFS)
  stz .lobyte(BG1VOFS)
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
  rts
.endproc
