.macpack generic

.include "./macro/utility.asm"
.include "./registers.inc"

.code

.import frameCounter
.import controllerPollTick, modemPollTick
.import terminalRenderVBlank
.import statusRenderVBlank, screenApplyVBlank

.export VBlank
.proc VBlank
  jml VBlankFast
.endproc

.proc VBlankFast
  pha
  phb
  phd
  phx
  phy
  php

  ; An NMI can interrupt main-loop code while X/Y are 8-bit. Normalize both
  ; widths after saving P so every VBlank callee gets its declared ABI.
  rep #$30
  .a16
  .i16
  inc32 frameCounter

  ; PPU work remains in VBlank. At most 32 queued terminal bytes are written;
  ; controller and NDM24 serial I/O stay in the main loop.
  sep #$20
  .a8
  jsr terminalRenderVBlank
  jsr statusRenderVBlank
  jsr screenApplyVBlank

  lda #$01
  sta controllerPollTick
  sta modemPollTick

  plp
  ply
  plx
  pld
  plb
  pla
  rti
.endproc
