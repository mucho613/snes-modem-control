.import initializeRegisters
.import transferText
.import clearBG1Tile
.import setBG1Tile
.import copyPalette
.import copyPattern
.import VBlank
.import initializeModem
.import clearRamAll

.include "./registers.inc"
.include "./common/utility.asm"
.include "./ram/clearAll.inc"

.segment "STARTUP"

.export EmptyInt
.proc EmptyInt
  @infiniteLoop:
  jmp @infiniteLoop
.endproc

.export Reset
.proc Reset
  jml ResetFast
.endproc

.proc ResetFast
  clc
  xce

  rep #$ff
  sep #$24 ; Disable IRQ and NMI
  .a8
  .i16

  ldx #$1fff
  txs ; Stack pointer value set

  setDP $0000

  stz NMITIMEN ; Disable interrupts
  stz HDMAEN ; Disable HDMA

  lda #$8f
  sta INIDISP ; Disable screen

  rep #$20
  .a16

  clearRamAll

  ; Reset PPU
  jsr initializeRegisters

  rep #$20
  .a16

  jsr clearBG1Tile
  jsr setBG1Tile
  jsr copyPalette ; Copy palette
  jsr copyPattern ; Copy pattern

  sep #$30
  .a8
  .i8

  lda #$fa
  sta BG1SC ; BG 1 Address and Size

  lda #$01
  sta TM ; Background and Object Enable (Main Screen)
  sta TS ; Background and Object Enable (Sub Screen)

  lda #$0f
  sta $2100 ; Screen Display Register

  rep #$30
  .a16
  .i16

  ; jsr initializeModem

  sep #$30
  .a8
  .i8

  ; Enable NMI
  lda #$80
  sta $4200 ; NMI, V/H Count, and Joypad Enable

  rep #$30
  .a16
  .i16

  cli

  @waitNmi:
  jmp @waitNmi
.endproc
