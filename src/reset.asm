.import initializeRegisters
.import transferText
.import clearBG1Tile
.import setBG1Tile
.import copyPalette
.import copyPattern
.import VBlank
.import initializeModem
.import clearRamAll
.import hdmaTable

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

  lda #$fe
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

  ; HDMA settings
  stz DMAP0
  lda #.lobyte(BG12NBA)
  sta BBAD0
  lda #.lobyte(hdmaTable)
  sta A1T0L
  lda #.hibyte(hdmaTable)
  sta A1T0H
  lda #.bankbyte(hdmaTable)
  sta A1B0

  lda #$01
  sta HDMAEN ; Enable HDMA channel 1

  ; Enable NMI
  lda #$80
  sta $4200 ; NMI, V/H Count, and Joypad Enable
  cli

  @waitNmi:
  jmp @waitNmi
.endproc
