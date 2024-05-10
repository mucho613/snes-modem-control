.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import frameCounter
.import executeModemSettings
.import atx4
.import atl0
.import ati0
.import ati1
.import ati2
.import ati3
.import ati4
.import ati5
.import ati6
.import ati7

.import atd0123456789

.export execModemSettings
.proc execModemSettings
  .a16
  .i16

  .scope
    ; send ATL0 command to modem
    lda frameCounter
    cmp #$0200
    bne @skip
    lda frameCounter + 2
    bne @skip

    pea executeModemSettings
    jsr print
    pla

    pea atl0
    jsr sendBytesToModem
    pla
    @skip:
  .endscope

  .scope
    ; send ATI0 command to modem
    lda frameCounter
    cmp #$0280
    bne @skip
    lda frameCounter + 2
    bne @skip

    pea atx4
    jsr sendBytesToModem
    pla
    @skip:
  .endscope

  .scope
    ; send ATD0123456789 command to modem
    lda frameCounter
    cmp #$0300
    bne @skip
    lda frameCounter + 2
    bne @skip

    pea atd0123456789
    jsr sendBytesToModem
    pla
    @skip:
  .endscope

  rts
.endproc
