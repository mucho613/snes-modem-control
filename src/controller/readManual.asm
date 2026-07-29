.include "../registers.inc"
.include "../macro/utility.asm"
.include "../modem/constants.inc"

.code

.import controllerPollTick
.import controller1Input, controller1InputPrev, controller1InputPulse

.export readController1
.proc readController1
  .a16
  .i16

  pha
  php
  sei
  phb
  phd
  phx
  setDBR $7e
  setDP $4000

  sep #$30
  .a8
  .i8

  lda controllerPollTick
  beq @done
  stz controllerPollTick

  lda controller1Input
  sta controller1InputPrev
  lda controller1Input + 1
  sta controller1InputPrev + 1
  stz controller1Input
  stz controller1Input + 1

  ; JOYOUT latches both ports, but only JOYSER0 is clocked here. The modem
  ; driver always latches port 2 again before reading it.
  stz .lobyte(JOYOUT)
  lda #MODEM_LATCH_ASSERT
  sta .lobyte(JOYOUT)
  stz .lobyte(JOYOUT)

  ldx #$10
@readBit:
  lda .lobyte(JOYSER0)
  lsr
  rol controller1Input
  rol controller1Input + 1
  dex
  bne @readBit

  lda controller1Input
  eor controller1InputPrev
  and controller1Input
  sta controller1InputPulse
  lda controller1Input + 1
  eor controller1InputPrev + 1
  and controller1Input + 1
  sta controller1InputPulse + 1

@done:
  rep #$30
  .a16
  .i16
  plx
  pld
  plb
  plp
  pla
  rts
.endproc
