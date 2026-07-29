.include "../macro/utility.asm"
.include "constants.inc"

.code

.import frameCounter
.import modemDriverState, modemFlags, modemLastError, modemTimeoutCount
.import modemSessionProbeSent, modemSessionRetryCount, modemSessionLastResult
.import modemSessionLineLength, modemSessionLine, modemSessionProbeStartFrame
.import modemQueueByte, modemReadByte
.import modemSetState, modemRecordTrace

.export modemSessionPoll
.proc modemSessionPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e

  sep #$30
  .a8
  .i8

  lda modemDriverState
  cmp #MODEM_STATE_PROBING
  bne done

  lda modemSessionProbeSent
  bne readResponse
  jsr queueProbe
  bcs done
  lda #$01
  sta modemSessionProbeSent
  rep #$20
  .a16
  lda frameCounter
  sta modemSessionProbeStartFrame
  lda frameCounter + 2
  sta modemSessionProbeStartFrame + 2
  sep #$20
  .a8

readResponse:
  jsr modemReadByte
  bcs checkTimeout
  jsr feedByte
  lda modemDriverState
  cmp #MODEM_STATE_PROBING
  beq readResponse
  bra done

checkTimeout:
  rep #$20
  .a16
  lda frameCounter
  sec
  sbc modemSessionProbeStartFrame
  cmp #MODEM_PROBE_TIMEOUT_FRAMES
  sep #$20
  .a8
  bcc done

  modemIncrement32 modemTimeoutCount
  inc modemSessionRetryCount
  lda modemSessionRetryCount
  cmp #MODEM_PROBE_RETRY_LIMIT
  bcs probeFailed
  stz modemSessionProbeSent
  stz modemSessionLineLength
  bra done

probeFailed:
  lda modemFlags
  ora #MODEM_FLAG_TIMEOUT
  sta modemFlags
  lda #MODEM_ERROR_PROBE_TIMEOUT
  sta modemLastError
  lda #MODEM_STATE_ERROR
  jsr modemSetState
  lda #MODEM_TRACE_ERROR
  jsr modemRecordTrace

done:
  rep #$30
  .a16
  .i16
  ply
  plx
  plb
  pla
  rts

queueProbe:
  lda #'A'
  jsr modemQueueByte
  bcs queueFailed
  lda #'T'
  jsr modemQueueByte
  bcs queueFailed
  lda #$0d
  jsr modemQueueByte
  bcs queueFailed
  lda #$0a
  jsr modemQueueByte
queueFailed:
  rts

; Input A is one raw modem byte. Parsing is deliberately active only in
; PROBING, so bytes received after readiness remain owned by the next layer.
feedByte:
  cmp #$0d
  beq finishLine
  cmp #$0a
  beq finishLine

  ldy modemSessionLineLength
  cpy #$1f
  bcs lineTooLong
  sta modemSessionLine, y
  iny
  sty modemSessionLineLength
  rts

lineTooLong:
  stz modemSessionLineLength
  rts

finishLine:
  ldy modemSessionLineLength
  bne lineNotEmpty
  jmp lineDone

lineNotEmpty:
  cpy #$02
  bne checkError
  lda modemSessionLine
  cmp #'A'
  bne checkOk
  lda modemSessionLine + 1
  cmp #'T'
  bne checkOk
  jmp lineDone

checkOk:
  lda modemSessionLine
  cmp #'O'
  bne checkError
  lda modemSessionLine + 1
  cmp #'K'
  bne checkError
  lda #MODEM_SESSION_RESULT_OK
  sta modemSessionLastResult
  lda #MODEM_STATE_READY
  jsr modemSetState
  jmp lineDone

checkError:
  cpy #$05
  bne checkBusy
  lda modemSessionLine
  cmp #'E'
  bne checkBusy
  lda modemSessionLine + 1
  cmp #'R'
  bne checkBusy
  lda modemSessionLine + 2
  cmp #'R'
  bne checkBusy
  lda modemSessionLine + 3
  cmp #'O'
  bne checkBusy
  lda modemSessionLine + 4
  cmp #'R'
  bne checkBusy
  lda #MODEM_SESSION_RESULT_ERROR
  sta modemSessionLastResult
  lda #MODEM_ERROR_PROBE_REJECTED
  sta modemLastError
  inc modemSessionRetryCount
  lda modemSessionRetryCount
  cmp #MODEM_PROBE_RETRY_LIMIT
  bcc retryRejectedProbe
  lda #MODEM_STATE_ERROR
  jsr modemSetState
  lda #MODEM_TRACE_ERROR
  jsr modemRecordTrace
  jmp lineDone

retryRejectedProbe:
  stz modemSessionProbeSent
  jmp lineDone

checkBusy:
  cpy #$04
  bne checkConnect
  lda modemSessionLine
  cmp #'B'
  bne checkConnect
  lda modemSessionLine + 1
  cmp #'U'
  bne checkConnect
  lda modemSessionLine + 2
  cmp #'S'
  bne checkConnect
  lda modemSessionLine + 3
  cmp #'Y'
  bne checkConnect
  lda #MODEM_SESSION_RESULT_BUSY
  sta modemSessionLastResult
  jmp lineDone

checkConnect:
  cpy #$07
  bcc checkNoCarrier
  lda modemSessionLine
  cmp #'C'
  bne checkNoCarrier
  lda modemSessionLine + 1
  cmp #'O'
  bne checkNoCarrier
  lda modemSessionLine + 2
  cmp #'N'
  bne checkNoCarrier
  lda modemSessionLine + 3
  cmp #'N'
  bne checkNoCarrier
  lda modemSessionLine + 4
  cmp #'E'
  bne checkNoCarrier
  lda modemSessionLine + 5
  cmp #'C'
  bne checkNoCarrier
  lda modemSessionLine + 6
  cmp #'T'
  bne checkNoCarrier
  lda #MODEM_SESSION_RESULT_CONNECT
  sta modemSessionLastResult
  jmp lineDone

checkNoCarrier:
  cpy #$0a
  bne checkNoDialtone
  lda modemSessionLine
  cmp #'N'
  bne checkNoDialtone
  lda modemSessionLine + 1
  cmp #'O'
  bne checkNoDialtone
  lda modemSessionLine + 2
  cmp #' '
  bne checkNoDialtone
  lda modemSessionLine + 3
  cmp #'C'
  bne checkNoDialtone
  lda modemSessionLine + 4
  cmp #'A'
  bne checkNoDialtone
  lda modemSessionLine + 5
  cmp #'R'
  bne checkNoDialtone
  lda modemSessionLine + 6
  cmp #'R'
  bne checkNoDialtone
  lda modemSessionLine + 7
  cmp #'I'
  bne checkNoDialtone
  lda modemSessionLine + 8
  cmp #'E'
  bne checkNoDialtone
  lda modemSessionLine + 9
  cmp #'R'
  bne checkNoDialtone
  lda #MODEM_SESSION_RESULT_NO_CARRIER
  sta modemSessionLastResult
  jmp lineDone

checkNoDialtone:
  cpy #$0b
  bne lineDone
  lda modemSessionLine
  cmp #'N'
  bne lineDone
  lda modemSessionLine + 1
  cmp #'O'
  bne lineDone
  lda modemSessionLine + 2
  cmp #' '
  bne lineDone
  lda modemSessionLine + 3
  cmp #'D'
  bne lineDone
  lda modemSessionLine + 4
  cmp #'I'
  bne lineDone
  lda modemSessionLine + 5
  cmp #'A'
  bne lineDone
  lda modemSessionLine + 6
  cmp #'L'
  bne lineDone
  lda modemSessionLine + 7
  cmp #'T'
  bne lineDone
  lda modemSessionLine + 8
  cmp #'O'
  bne lineDone
  lda modemSessionLine + 9
  cmp #'N'
  bne lineDone
  lda modemSessionLine + 10
  cmp #'E'
  bne lineDone
  lda #MODEM_SESSION_RESULT_NO_DIALTONE
  sta modemSessionLastResult

lineDone:
  stz modemSessionLineLength
  rts
.endproc
