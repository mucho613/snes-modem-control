.import initializeRegisters
.import transferText
.import bg1YScrollPos
.import clearBG1Tile
.import setBG1Tile
.import copyPalette
.import copyPattern
.import VBlank
.import initializeModem
.import clearRamAll
.import bufW12SEL
.import bufWH0
.import bufWH1

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

  rep #$20
  .a16

  clearRamAll

  ; Reset PPU
  jsr initializeRegisters

  rep #$20
  .a16

  jsr clearBG1Tile
  jsr setBG1Tile
  jsr copyPalette
  jsr copyPattern

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

  ; Reset BG1 scroll position
  lda #$01FF
  sta bg1YScrollPos

  ; jsr initializeModem

  sep #$30
  .a8
  .i8

  ; Enable NMI
  lda #$81
  sta NMITIMEN ; NMI, V/H Count, and Joypad Enable
  cli

  ; Set window settings
  lda #$03
  sta W12SEL ; Window 1 Enable and inverted
  lda #$18
  sta WH0 ; Window 1 Position 1 = 24
  lda #$E4
  sta WH1 ; Window 1 Position 2 = 228
  lda #$01
  sta TMW ; Window 1 Enable (Main Screen)
  lda #$01
  sta TSW ; Window 1 Enable (Sub Screen)

  @waitNmi:
  jmp @waitNmi
.endproc
