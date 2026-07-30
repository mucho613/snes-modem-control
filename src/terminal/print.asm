.include "../registers.inc"
.include "../macro/utility.asm"
.include "../modem/constants.inc"

.code

.ifdef MODEM_FONT_TEST
  .import fontTestScreen
.endif
.import terminalDisplayReadIndex, terminalDisplayWriteIndex
.import terminalDisplayBuffer, terminalCursor, terminalVerticalScroll
.import terminalQueueScratchByte, terminalRenderScratchByte
.import modemTerminalDroppedCount

.assert TERMINAL_QUEUE_STORAGE_SIZE = $0100, error, "terminal queue requires 8-bit indices"
.assert TERMINAL_QUEUE_CAPACITY = TERMINAL_QUEUE_STORAGE_SIZE - 1, error, "terminal queue capacity"
.assert TERMINAL_COLUMNS * TERMINAL_ROWS = TERMINAL_TILEMAP_MASK + 1, error, "terminal tilemap geometry"

.export terminalInitialize
.export terminalQueueByte
.export terminalMirrorReceivedByte
.export terminalRenderVBlank
.export print

; Initialize the independent raw-log display mirror. The human-facing header
; belongs to the status screen; only the dedicated font-test ROM enqueues a
; static specimen here.
; The caller uses 16-bit accumulator and index registers.
.proc terminalInitialize
  .a16
  .i16

  pha
  phb
  phx

  setDBR $7e
  m8
  stz terminalDisplayReadIndex
  stz terminalDisplayWriteIndex
  stz terminalCursor
  stz terminalCursor + 1
  stz terminalVerticalScroll
  stz terminalVerticalScroll + 1
  stz terminalQueueScratchByte
  stz terminalRenderScratchByte
  stz modemTerminalDroppedCount
  stz modemTerminalDroppedCount + 1
  stz modemTerminalDroppedCount + 2
  stz modemTerminalDroppedCount + 3

  mi16
  .ifdef MODEM_FONT_TEST
    setDBR .bankbyte(fontTestScreen)
    pea fontTestScreen
    jsr print
    pla
  .endif

  plx
  plb
  pla
  rts
.endproc

; Queue one display-only byte. Input A is 8-bit. The routine preserves A and
; X and cannot be split by VBlank.
.proc terminalQueueByte
  .a8
  .i16

  php
  sei
  phx
  phb
  setDBR $7e

  sta terminalQueueScratchByte
  lda terminalDisplayWriteIndex
  inc
  cmp terminalDisplayReadIndex
  bne spaceAvailable

  lda terminalDisplayReadIndex
  inc
  sta terminalDisplayReadIndex
  modemIncrement32 modemTerminalDroppedCount

spaceAvailable:
  lda terminalDisplayWriteIndex
  m16
  and #$00ff
  tax
  m8
  lda terminalQueueScratchByte
  sta terminalDisplayBuffer, x
  inc terminalDisplayWriteIndex

  lda terminalQueueScratchByte
  plb
  plx
  plp_m8_i16
  rts
.endproc

; Explicit name used by the modem RX producer.
.proc terminalMirrorReceivedByte
  .a8
  .i8

  php
  sei
  i16
  jsr terminalQueueByte
  plp_m8_i8
  rts
.endproc

; Compatibility string output for existing local messages. The argument is a
; stack-passed, NUL-terminated pointer. Bytes enter the same display queue as
; modem RX and are therefore rendered only during VBlank.
.proc print
  .a16
  .i16

  pha
  phb
  phx
  phy

  m8
  ldy #$0000

@loop:
  lda ($0a, s), y
  beq @done
  jsr terminalQueueByte
  iny
  cpy #$00ff
  bne @loop

@done:
  m16
  ply
  plx
  plb
  pla
  rts
.endproc

; Drain at most 32 display bytes while VRAM is safely writable. The terminal
; is a 32x64 tilemap at VRAM $4800 and follows the cursor automatically.
.proc terminalRenderVBlank
  .a8
  .i16

  ; Save P before normalizing X/Y. This keeps the stack frame balanced even
  ; if a future caller enters while the index registers are 8-bit.
  php
  i16
  pha
  phb
  phd
  phx
  phy

  setDBR $7e
  setDP $2100
  m8
  i16
  ldx #TERMINAL_RENDER_BUDGET
@nextByte:
  lda terminalDisplayReadIndex
  cmp terminalDisplayWriteIndex
  beq @updateScroll

  m16
  and #$00ff
  tay
  m8
  lda terminalDisplayBuffer, y
  sta terminalRenderScratchByte
  inc terminalDisplayReadIndex
  jsr @renderByte
  dex
  bne @nextByte

@updateScroll:
  m16
  lda terminalCursor
  and #(TERMINAL_TILEMAP_MASK ^ (TERMINAL_COLUMNS - 1))
  lsr
  lsr
  sec
  sbc #TERMINAL_SCROLL_ANCHOR
  sta terminalVerticalScroll

  ; A was 8-bit when saved above. Restore that width before popping it so
  ; this callee cannot unbalance the NMI stack.
  m8
  i16
  ply
  plx
  pld
  plb
  pla
  plp_m8_i16
  rts

@renderByte:
  lda terminalRenderScratchByte
  cmp #$0d
  beq @carriageReturn
  cmp #$0a
  beq @lineFeed
  cmp #$08
  beq @backspace
  cmp #$20
  bcc @renderDone
  cmp #$7f
  bcs @renderDone

  m16
  lda terminalCursor
  clc
  adc #TERMINAL_TILEMAP_BASE
  sta .lobyte(VMADDL)
  m8
  lda terminalRenderScratchByte
  sta .lobyte(VMDATAL)
  stz .lobyte(VMDATAH)
  m16
  lda terminalCursor
  inc
  and #TERMINAL_TILEMAP_MASK
  sta terminalCursor
  m8
  rts

@carriageReturn:
  m16
  lda terminalCursor
  and #(TERMINAL_TILEMAP_MASK ^ (TERMINAL_COLUMNS - 1))
  sta terminalCursor
  m8
  rts

@lineFeed:
  m16
  lda terminalCursor
  and #(TERMINAL_TILEMAP_MASK ^ (TERMINAL_COLUMNS - 1))
  clc
  adc #TERMINAL_COLUMNS
  and #TERMINAL_TILEMAP_MASK
  sta terminalCursor
  m8
  rts

@backspace:
  m16
  lda terminalCursor
  dec
  and #TERMINAL_TILEMAP_MASK
  sta terminalCursor
  m8
@renderDone:
  rts
.endproc
