.segment "STARTUP"

.import copyNameTable
.import readControllersInput
.import drawFrameCount
.import drawControllerInput
.import print
.import sendBytesToModem
.import frameCounter
.import executeModemSettings
.import atl0
.import atd0123456789

someData: .byte "Send some data to modem!", $0d, $0a, $00

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
    ; send ATH1 command to modem
    lda frameCounter
    cmp #$0280
    bne @skip
    lda frameCounter + 2
    bne @skip

    pea executeModemSettings
    jsr print
    pla

    pea atd0123456789
    jsr sendBytesToModem
    pla
    @skip:
  .endscope

  rts
.endproc
