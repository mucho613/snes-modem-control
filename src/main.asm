.setcpu "65816"

.import initializeRegisters
.import transferText
.import copyPalette
.import copyPattern
.import copyText
.import VBlank
.import initializeModem

.include "./registers.inc"
.include "ppu/clearBG1Tile.asm"

.segment "RODATA"

.segment "STARTUP"

.export EmptyInt
.proc EmptyInt
  rti
.endproc

.export ResetHandler
.proc ResetHandler
  sei
  clc
  xce

  phk
  plb

  rep #$30
  .a16
  .i16

  jsr initializeRegisters

  ldx #$1fff ; Stack pointer value set
  txs

  clearBG1Tile
  jsr copyPalette ; Copy palette
  jsr copyPattern ; Copy pattern

  jsr copyText    ; Copy text

  sep #$30
  .a8
  .i8

  lda #$40
  sta $2107 ; BG 1 Address and Size

  lda #$01
  sta $212c ; Background and Object Enable (Main Screen)
  stz $212d ; Background and Object Disable (Sub Screen)

  lda #$0f
  sta $2100 ; Screen Display Register

  rep #$30
  .a16
  .i16

  jsr initializeModem

  sep #$30
  .a8
  .i8

  ; Enable NMI
  lda #$80
  sta $4200 ; NMI, V/H Count, and Joypad Enable

  cli

  rti
.endproc
