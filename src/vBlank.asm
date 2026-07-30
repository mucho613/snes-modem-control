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

  ; RDNMI is the actual NMI source latch. Merely leaving VBlank, as observed
  ; through HVBJOY, is not sufficient when NMITIMEN is gated around manual
  ; controller I/O: re-enabling bit 7 while this latch is still set can fire
  ; a second NMI for the same VBlank. Acknowledge it before counting the frame.
  m8
  setDBR $00
  lda RDNMI
  setDBR $7e

  ; An NMI can interrupt main-loop code while X/Y are 8-bit. Normalize both
  ; widths after saving P so every VBlank callee gets its declared ABI.
  mi16
  inc32 frameCounter

  ; PPU work remains in VBlank. At most 32 queued terminal bytes are written;
  ; controller and NDM24 serial I/O stay in the main loop.
  m8
  jsr terminalRenderVBlank
  jsl statusRenderVBlank
  jsl screenApplyVBlank

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
