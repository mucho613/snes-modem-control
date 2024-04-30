.setcpu "65816"

.import initializeRegisters
.import transferText
.import copyPalette
.import copyPattern
.import VBlank
.import initializeModem

.include "./registers.inc"
.include "ppu/clearBG1Tile.asm"

.segment "RODATA"

.segment "STARTUP"

.export EmptyInt
.proc EmptyInt
  @infiniteLoop:
  jmp @infiniteLoop
.endproc

.export ResetHandler
.proc ResetHandler
  jsl _FastRomReset
.endproc

.proc _FastRomReset
  sei
  clc
  xce

  rep #$ff
  sep #$24
  .a8
  .i16

  ldx #$1fff
  txs ; Stack pointer value set

  pea $00
  pld ; Reset Direct Page register to 0

  ; phk
  ; plb ; Set Data Bank to Program Bank

  stz NMITIMEN ; Disable interrupts
  stz HDMAEN ; Disable HDMA

  lda #$8f
  sta INIDISP ; Disable screen

  rep #$30
  .a16
  .i16

  ; Fill WRAM with zeros using two 64KiB fixed address DMA transfers to WMDATA
  stz WMADDL
  stz WMADDM
  stz WMADDH

  lda #$08
  sta DMAP0

  lda #WMDATA & $ff
  sta BBAD0

  ldx #.loword(WorkRamResetByte) ; Set DMA source to WorkRamResetByte
  stx A1T0L
  lda #.bankbyte(WorkRamResetByte)
  sta A1B0

  ldx #$00
  stx DAS0L ; Transfer size = 64KiB

  lda #$01
  sta MDMAEN ; First DMA transfer

  ; x = 0
  stx DAS0L ; Transfer size = 64KiB

  ; a = 1
  sta MDMAEN ; Second DMA transfer

  ; Reset PPU
  jsr initializeRegisters

  rep #$20
  .a16

  clearBG1Tile
  jsr copyPalette ; Copy palette
  jsr copyPattern ; Copy pattern

  sep #$30
  .a8
  .i8

  lda #$42
  sta $2107 ; BG 1 Address and Size

  lda #$01
  sta $212c ; Background and Object Enable (Main Screen)
  stz $212d ; Background and Object Disable (Sub Screen)

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

  cli

  rti
.endproc

WorkRamResetByte:
  .byte 00
