.segment "STARTUP"

ramResetByte: .byte $00

.macro clearRamAll
  .a16
  .i16

  sep #$20
  .a8
  .i16

  ; Fill WRAM with zeros using two 64KiB fixed address DMA transfers to WMDATA
  stz WMADDL
  stz WMADDM
  stz WMADDH

  lda #$08
  sta DMAP0

  lda #.lobyte(WMDATA)
  sta BBAD0

  ldx #.loword(ramResetByte) ; Set DMA source to WorkramResetByte
  stx A1T0L
  lda #.bankbyte(ramResetByte)
  sta A1B0

  ldx #$0000
  stx DAS0L ; Transfer size = 64KiB

  lda #$01
  sta MDMAEN ; First DMA transfer

  stx DAS0L ; Transfer size = 64KiB
  sta MDMAEN ; Second DMA transfer

  rep #$30
  .a16
  .i16
.endmacro

