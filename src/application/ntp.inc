STATUS_VALUE_WIDTH = TERMINAL_COLUMNS - 7

.code

.import pppNtpState
.import clockDisplayText
.import statusApplicationName, statusApplicationState, statusApplicationValue

.export applicationStatusInitialize, applicationStatusPoll

; NTP application-status adapter. The status-screen renderer depends only on
; the two exported entry points and the three fixed-width output buffers.
.proc applicationStatusInitialize
  .a8
  .i16

  ldx #$0000
  lda #' '
@clear:
  sta statusApplicationName, x
  sta statusApplicationState, x
  sta statusApplicationValue, x
  inx
  cpx #STATUS_VALUE_WIDTH
  bne @clear

  lda #'N'
  sta statusApplicationName + 0
  lda #'T'
  sta statusApplicationName + 1
  lda #'P'
  sta statusApplicationName + 2
  rts
.endproc

.proc applicationStatusPoll
  .a8
  .i16

  ldx #$0000
  lda #' '
@clearState:
  sta statusApplicationState, x
  inx
  cpx #STATUS_VALUE_WIDTH
  bne @clearState

  lda pppNtpState
  cmp #PPP_NTP_STATE_RECEIVED
  beq @received
  cmp #PPP_NTP_STATE_FAILED
  beq @error

  lda #'W'
  sta statusApplicationState + 0
  lda #'A'
  sta statusApplicationState + 1
  lda #'I'
  sta statusApplicationState + 2
  lda #'T'
  sta statusApplicationState + 3
  lda #'I'
  sta statusApplicationState + 4
  lda #'N'
  sta statusApplicationState + 5
  lda #'G'
  sta statusApplicationState + 6
  bra @copyTime

@received:
  lda #'R'
  sta statusApplicationState + 0
  lda #'E'
  sta statusApplicationState + 1
  lda #'C'
  sta statusApplicationState + 2
  lda #'E'
  sta statusApplicationState + 3
  lda #'I'
  sta statusApplicationState + 4
  lda #'V'
  sta statusApplicationState + 5
  lda #'E'
  sta statusApplicationState + 6
  lda #'D'
  sta statusApplicationState + 7
  bra @copyTime

@error:
  lda #'E'
  sta statusApplicationState + 0
  lda #'R'
  sta statusApplicationState + 1
  sta statusApplicationState + 2
  lda #'O'
  sta statusApplicationState + 3
  lda #'R'
  sta statusApplicationState + 4

@copyTime:
  ldx #$0000
@copyTimeLoop:
  lda clockDisplayText, x
  sta statusApplicationValue, x
  inx
  cpx #STATUS_VALUE_WIDTH
  bne @copyTimeLoop
  rts
.endproc
