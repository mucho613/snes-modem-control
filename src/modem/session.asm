.include "../macro/utility.asm"
.include "constants.inc"

.code

.import frameCounter
.import modemDriverState, modemFlags, modemLastError, modemTimeoutCount
.import modemSessionStage
.import modemSessionProbeSent, modemSessionRetryCount, modemSessionLastResult
.import modemSessionLineLength, modemSessionLine, modemSessionProbeStartFrame
.import modemAtStatus, modemAtExpectedResult, modemAtStartFrame, modemAtTimeoutFrames
.import modemMailboxArguments
.import modemTransmitReadIndex, modemTransmitWriteIndex
.import modemQueueByte, modemReadByte
.import modemSetState, modemRecordTrace

.export modemSessionPoll, modemAtBegin
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
  lda #$10
  sta modemSessionStage

  lda modemAtStatus
  cmp #MODEM_AT_STATUS_RUNNING
  bne @checkProbe
  jmp atReadResponse

@checkProbe:
  lda modemDriverState
  cmp #MODEM_STATE_PROBING
  beq @probing
  jmp done
@probing:

  lda modemSessionProbeSent
  bne readResponse
  lda #$20
  sta modemSessionStage
  jsr queueProbe
  lda #$21
  sta modemSessionStage
  bcc probeQueued
  jmp done
probeQueued:
  lda #$01
  sta modemSessionProbeSent
  stz modemSessionLastResult
  lda #$22
  sta modemSessionStage
  rep #$20
  .a16
  lda frameCounter
  sta modemSessionProbeStartFrame
  lda frameCounter + 2
  sta modemSessionProbeStartFrame + 2
  sep #$20
  .a8

readResponse:
  lda #$30
  sta modemSessionStage
  jsr modemReadByte
  ; Preserve the returned byte while publishing the diagnostic stage.
  pha
  lda #$31
  sta modemSessionStage
  pla
  bcs checkTimeout
  jsr feedByte
  lda modemSessionLastResult
  beq readResponse
  cmp #MODEM_SESSION_RESULT_OK
  beq probePassed
  jmp probeRejected

probePassed:
  lda #MODEM_STATE_READY
  jsr modemSetState
  jmp done

probeRejected:
  lda #MODEM_ERROR_PROBE_REJECTED
  sta modemLastError
  inc modemSessionRetryCount
  lda modemSessionRetryCount
  cmp #MODEM_PROBE_RETRY_LIMIT
  bcs probeRejectedFinal
  stz modemSessionProbeSent
  stz modemSessionLineLength
  stz modemSessionLastResult
  jmp done

probeRejectedFinal:
  lda #MODEM_STATE_ERROR
  jsr modemSetState
  lda #MODEM_TRACE_ERROR
  jsr modemRecordTrace
  jmp done

checkTimeout:
  lda #$40
  sta modemSessionStage
  rep #$20
  .a16
  lda frameCounter
  sec
  sbc modemSessionProbeStartFrame
  cmp #MODEM_PROBE_TIMEOUT_FRAMES
  sep #$20
  .a8
  bcs @probeTimeoutExpired
  jmp done

@probeTimeoutExpired:
  modemIncrement32 modemTimeoutCount
  inc modemSessionRetryCount
  lda modemSessionRetryCount
  cmp #MODEM_PROBE_RETRY_LIMIT
  bcs probeFailed
  stz modemSessionProbeSent
  stz modemSessionLineLength
  jmp done

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
  jmp done

atReadResponse:
  lda #$60
  sta modemSessionStage
  jsr modemReadByte
  bcs atCheckTimeout
  jsr feedByte
  lda modemSessionLastResult
  beq atReadResponse
  lda modemAtExpectedResult
  beq atPassed
  lda modemSessionLastResult
  cmp modemAtExpectedResult
  beq atPassed
  jmp atRejected

atPassed:
  lda #MODEM_AT_STATUS_PASSED
  sta modemAtStatus
  lda modemAtExpectedResult
  cmp #MODEM_SESSION_RESULT_CONNECT
  beq atConnected
  cmp #MODEM_SESSION_RESULT_NO_CARRIER
  beq atReturnedReady
  lda #MODEM_STATE_READY
  jsr modemSetState
  bra done

atConnected:
  lda #MODEM_STATE_CONNECTED
  jsr modemSetState
  jmp done

atReturnedReady:
  lda #MODEM_STATE_READY
  jsr modemSetState
  jmp done

atRejected:
  lda #MODEM_ERROR_AT_REJECTED
  sta modemLastError
  lda #MODEM_AT_STATUS_FAILED
  sta modemAtStatus
  lda #MODEM_STATE_ERROR
  jsr modemSetState
  lda #MODEM_TRACE_ERROR
  jsr modemRecordTrace
  jmp done

atCheckTimeout:
  rep #$20
  .a16
  lda frameCounter
  sec
  sbc modemAtStartFrame
  cmp modemAtTimeoutFrames
  sep #$20
  .a8
  bcs @atTimeoutExpired
  jmp done

@atTimeoutExpired:
  modemIncrement32 modemTimeoutCount
  lda modemFlags
  ora #MODEM_FLAG_TIMEOUT
  sta modemFlags
  lda #MODEM_ERROR_AT_TIMEOUT
  sta modemLastError
  lda #MODEM_AT_STATUS_FAILED
  sta modemAtStatus
  lda #MODEM_STATE_ERROR
  jsr modemSetState
  lda #MODEM_TRACE_ERROR
  jsr modemRecordTrace

done:
  lda #$90
  sta modemSessionStage
  rep #$30
  .a16
  .i16
  ply
  plx
  plb
  pla
  rts

queueProbe:
  .a8
  .i8

  ; ATM0 doubles as the liveness probe and reapplies speaker-off after every
  ; power-on or explicit raw-R reinitialization.
  lda #$50
  sta modemSessionStage
  lda #'A'
  jsr modemQueueByte
  lda #$51
  sta modemSessionStage
  bcs queueFailed
  lda #'T'
  jsr modemQueueByte
  lda #$52
  sta modemSessionStage
  bcs queueFailed
  lda #'M'
  jsr modemQueueByte
  lda #$53
  sta modemSessionStage
  bcs queueFailed
  lda #'0'
  jsr modemQueueByte
  lda #$54
  sta modemSessionStage
  bcs queueFailed
  lda #$0d
  jsr modemQueueByte
  lda #$55
  sta modemSessionStage
  bcs queueFailed
  lda #$0a
  jsr modemQueueByte
  lda #$56
  sta modemSessionStage
queueFailed:
  rts

; Input A is one raw modem byte. Parsing is deliberately active only in
; PROBING, so bytes received after readiness remain owned by the next layer.
feedByte:
  .a8
  .i8

  ; NDM24 terminates AT result lines with CR LF. Keep the text accumulated
  ; across CR and commit it on LF so READY is not published before the final
  ; LF has been consumed from the RX ring.
  cmp #$0d
  beq ignoreCarriageReturn
  cmp #$0a
  beq finishLine

  ldy modemSessionLineLength
  cpy #$1f
  bcs lineTooLong
  sta modemSessionLine, y
  iny
  sty modemSessionLineLength
  rts

ignoreCarriageReturn:
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

; Begin one host-supplied AT transaction.
; Mailbox arguments:
;   +0 expected MODEM_SESSION_RESULT_*
;   +1 timeout frames, little endian u16
;   +3 command byte count
;   +4 command bytes (may be empty when waiting for NO CARRIER)
; Carry clear means accepted; carry set means invalid or queue full.
.proc modemAtBegin
  .a8
  .i8

  phb
  phx
  phy
  setDBR $7e

  lda modemMailboxArguments + MODEM_AT_ARGUMENT_EXPECTED_RESULT
  cmp #MODEM_SESSION_RESULT_NONE
  beq @validateReadyState
  cmp #MODEM_SESSION_RESULT_OK
  beq @validateReadyState
  cmp #MODEM_SESSION_RESULT_CONNECT
  beq @validateReadyState
  cmp #MODEM_SESSION_RESULT_NO_CARRIER
  beq @validateConnectedState
  jmp @invalid

@validateReadyState:
  lda modemDriverState
  cmp #MODEM_STATE_READY
  beq @validateTimeout
  jmp @invalid

@validateConnectedState:
  lda modemDriverState
  cmp #MODEM_STATE_CONNECTED
  beq @validateTimeout
  jmp @invalid

@validateTimeout:
  lda modemTransmitReadIndex
  cmp modemTransmitWriteIndex
  beq @validateTimeoutValue
  jmp @invalid

@validateTimeoutValue:
  lda modemMailboxArguments + MODEM_AT_ARGUMENT_TIMEOUT_FRAMES
  ora modemMailboxArguments + MODEM_AT_ARGUMENT_TIMEOUT_FRAMES + 1
  bne @validateLength
  jmp @invalid

@validateLength:
  lda modemMailboxArguments + MODEM_AT_ARGUMENT_COMMAND_LENGTH
  cmp #(MODEM_AT_COMMAND_MAX_LENGTH + 1)
  bcc @lengthValid
  jmp @invalid
@lengthValid:
  tay
  bne @queueCommand
  lda modemMailboxArguments + MODEM_AT_ARGUMENT_EXPECTED_RESULT
  cmp #MODEM_SESSION_RESULT_NO_CARRIER
  beq @start
  jmp @invalid

@queueCommand:
  ldx #$00
@queueByte:
  lda modemMailboxArguments + MODEM_AT_ARGUMENT_COMMAND, x
  jsr modemQueueByte
  bcc @queuedByte
  jmp @invalid
@queuedByte:
  inx
  dey
  bne @queueByte

@start:
  lda modemMailboxArguments + MODEM_AT_ARGUMENT_EXPECTED_RESULT
  sta modemAtExpectedResult
  lda modemMailboxArguments + MODEM_AT_ARGUMENT_TIMEOUT_FRAMES
  sta modemAtTimeoutFrames
  lda modemMailboxArguments + MODEM_AT_ARGUMENT_TIMEOUT_FRAMES + 1
  sta modemAtTimeoutFrames + 1
  stz modemSessionLastResult
  stz modemSessionLineLength

  rep #$20
  .a16
  lda frameCounter
  sta modemAtStartFrame
  lda frameCounter + 2
  sta modemAtStartFrame + 2
  sep #$20
  .a8

  lda #MODEM_AT_STATUS_RUNNING
  sta modemAtStatus
  lda modemAtExpectedResult
  cmp #MODEM_SESSION_RESULT_CONNECT
  beq @setDialing
  cmp #MODEM_SESSION_RESULT_NO_CARRIER
  beq @setDisconnecting
  lda #MODEM_STATE_AT_COMMAND
  jsr modemSetState
  bra @accepted

@setDialing:
  lda #MODEM_STATE_DIALING
  jsr modemSetState
  bra @accepted

@setDisconnecting:
  lda #MODEM_STATE_DISCONNECTING
  jsr modemSetState

@accepted:
  ply
  plx
  plb
  clc
  rts

@invalid:
  lda #MODEM_ERROR_AT_INVALID
  sta modemLastError
  lda #MODEM_AT_STATUS_FAILED
  sta modemAtStatus
  ply
  plx
  plb
  sec
  rts
.endproc
