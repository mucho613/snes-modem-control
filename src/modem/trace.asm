.include "constants.inc"
.include "../macro/utility.asm"

.code

.import frameCounter
.import modemDriverState, modemFlags, modemLastDiscardReason
.import modemLastDataReport, modemLastStatusReport
.import modemTraceFrozen, modemTraceNextSequence, modemTraceOverwrittenCount
.import modemTrace, modemTraceScratchKind

.export modemRecordTrace, modemSetState
.export modemClearTrace, modemFreezeTrace, modemResumeTrace

; Input A = MODEM_TRACE_* event kind. Callers use 8-bit A and index registers.
; The complete event is committed before traceNextSequence is incremented.
.proc modemRecordTrace
  .a8
  .i8

  php
  sei
  pha
  phb
  phx
  phy
  setDBR $7e

  sta modemTraceScratchKind

  lda modemTraceFrozen
  beq traceEnabled
  jmp done

traceEnabled:
  lda modemTraceNextSequence + 1
  ora modemTraceNextSequence + 2
  ora modemTraceNextSequence + 3
  beq notOverwriting
  lda modemFlags
  ora #MODEM_FLAG_TRACE_OVERWRITE
  sta modemFlags
  modemIncrement32 modemTraceOverwrittenCount

notOverwriting:
  rep #$30
  .a16
  .i16

  lda modemTraceNextSequence
  and #$00ff
  asl
  asl
  asl
  asl
  tay

  lda modemTraceNextSequence
  sta modemTrace + MODEM_TRACE_RECORD_SEQUENCE, y
  lda modemTraceNextSequence + 2
  sta modemTrace + MODEM_TRACE_RECORD_SEQUENCE + 2, y
  lda frameCounter
  sta modemTrace + MODEM_TRACE_RECORD_FRAME, y
  lda frameCounter + 2
  sta modemTrace + MODEM_TRACE_RECORD_FRAME + 2, y

  sep #$20
  .a8
  lda modemTraceScratchKind
  sta modemTrace + MODEM_TRACE_RECORD_KIND, y
  lda modemDriverState
  sta modemTrace + MODEM_TRACE_RECORD_STATE, y
  lda modemLastDiscardReason
  sta modemTrace + MODEM_TRACE_RECORD_REASON, y
  lda modemFlags
  sta modemTrace + MODEM_TRACE_RECORD_FLAGS, y

  rep #$20
  .a16
  lda modemLastDataReport
  sta modemTrace + MODEM_TRACE_RECORD_DATA, y
  lda modemLastStatusReport
  sta modemTrace + MODEM_TRACE_RECORD_STATUS, y

  sep #$30
  .a8
  .i8
  modemIncrement32 modemTraceNextSequence

  lda modemTraceScratchKind
  cmp #MODEM_TRACE_ERROR
  bne done
  lda #$01
  sta modemTraceFrozen

done:
  sep #$30
  .a8
  .i8
  ply
  plx
  plb
  pla
  plp
  rts
.endproc

; Input A = MODEM_STATE_*.
.proc modemSetState
  .a8
  sta modemDriverState
  pha
  lda #MODEM_TRACE_STATE
  jsr modemRecordTrace
  pla
  rts
.endproc

.proc modemClearTrace
  .a8
  stz modemTraceNextSequence
  stz modemTraceNextSequence + 1
  stz modemTraceNextSequence + 2
  stz modemTraceNextSequence + 3
  stz modemTraceOverwrittenCount
  stz modemTraceOverwrittenCount + 1
  stz modemTraceOverwrittenCount + 2
  stz modemTraceOverwrittenCount + 3
  lda modemFlags
  and #($ff ^ MODEM_FLAG_TRACE_OVERWRITE)
  sta modemFlags
  rts
.endproc

.proc modemFreezeTrace
  .a8
  lda #$01
  sta modemTraceFrozen
  rts
.endproc

.proc modemResumeTrace
  .a8
  stz modemTraceFrozen
  rts
.endproc
