.p816

.export initializeRegisters

.include "./registers.inc"

.segment "STARTUP"

.proc initializeRegisters
  sep #$20
  .a8

  stz NMITIMEN ; disable interrupts
  stz HDMAEN ; disable HDMA

  lda #$8f
  sta INIDISP ; enable force blank, full brightness)

  lda #$01
  sta MEMSEL ; set FastROM mode

  lda #$FF
  sta WRIO

  stz OBJSEL

  stz OAMADDL ; disable OAM priority rotation
  stz OAMADDH

  stz BGMODE
  stz MOSAIC

  stz BG1SC
  stz BG2SC
  stz BG3SC
  stz BG4SC

  stz BG12NBA
  stz BG34NBA

  lda #$FF

  stz BG1HOFS ; set horizontal offset to 0
  stz BG1HOFS
  sta BG1VOFS ; set vertical offset to -1
  sta BG1VOFS

  stz BG2HOFS ; set horizontal offset to 0
  stz BG2HOFS
  sta BG2VOFS ; set vertical offset to -1
  sta BG2VOFS

  stz BG3HOFS ; set horizontal offset to 0
  stz BG3HOFS
  sta BG3VOFS ; set vertical offset to -1
  sta BG3VOFS

  stz BG4HOFS ; set horizontal offset to 0
  stz BG4HOFS
  sta BG4VOFS ; set vertical offset to -1
  sta BG4VOFS

  lda #$80
  sta VMAIN ; VRAM word access, increment by 1, no remapping

  lda #$01
  stz M7SEL ; no flipping or screen repeat

  stz M7A
  sta M7A

  stz M7B
  stz M7B

  stz M7C
  stz M7C

  stz M7D
  sta M7D

  stz M7X
  stz M7X

  stz M7Y
  stz M7Y

  stz W12SEL
  stz W34SEL
  stz WOBJSEL
  stz WH0
  stz WH1
  stz WH2
  stz WH3
  stz WBGLOG
  stz WOBJLOG

  stz TM
  stz TS
  stz TMW
  stz TSW

  lda #$30
  sta CGWSEL ; Color math disable region = everywhere

  stz CGADSUB

  lda #$e0
  sta COLDATA ; set Fixed color data to black

  stz SETINI

  rep #$20
  .a16

  rts
.endproc
