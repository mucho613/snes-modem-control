.include "../macro/utility.asm"
.include "../modem/generated.inc"

; One nominal NTSC SFC frame represented as a 32-bit binary fraction of one
; second. The rate derives from 236250000/11 master clocks per second and an
; average 357366 master clocks per non-interlaced frame:
; round(2^32 * (357366 * 11) / 236250000) = $04427885.
CLOCK_NTSC_FRAME_FRACTION_LOW = $7885
CLOCK_NTSC_FRAME_FRACTION_HIGH = $0442

CLOCK_JST_OFFSET_SECONDS = $00007e90
CLOCK_COMMON_YEAR_SECONDS = $01e13380
CLOCK_LEAP_YEAR_SECONDS = $01e28500
CLOCK_28_DAY_MONTH_SECONDS = $0024ea00
CLOCK_29_DAY_MONTH_SECONDS = $00263b80
CLOCK_30_DAY_MONTH_SECONDS = $00278d00
CLOCK_31_DAY_MONTH_SECONDS = $0028de80
CLOCK_DAY_SECONDS = $00015180
CLOCK_HOUR_SECONDS = $00000e10
CLOCK_MINUTE_SECONDS = $0000003c

.macro clockSubtractIfAtLeast value, tooSmall
  lda clockConversionRemaining + 2
  cmp #((value >> 16) & $ffff)
  bcs :+
  jmp tooSmall
:
  beq :+
  bra :++
:
  lda clockConversionRemaining
  cmp #(value & $ffff)
  bcs :+
  jmp tooSmall
:
  lda clockConversionRemaining
  sec
  sbc #(value & $ffff)
  sta clockConversionRemaining
  lda clockConversionRemaining + 2
  sbc #((value >> 16) & $ffff)
  sta clockConversionRemaining + 2
.endmacro

.code

.import frameCounter
.import clockValid, clockUnixSeconds, clockSubsecond
.import clockLastFrame, clockYear, clockMonth, clockDay
.import clockHour, clockMinute, clockSecond, clockDisplayText
.import clockConversionRemaining

.export clockInitialize, clockPoll, clockSetUnixTime, clockAdvanceFrames

.proc clockInitialize
  .a16
  .i16

  pha
  phb
  phx
  setDBR $7e

  stz clockUnixSeconds
  stz clockUnixSeconds + 2
  stz clockSubsecond
  stz clockSubsecond + 2
  stz clockYear
  stz clockConversionRemaining
  stz clockConversionRemaining + 2
  lda frameCounter
  sta clockLastFrame

  sep #$20
  .a8
  stz clockValid
  stz clockMonth
  stz clockDay
  stz clockHour
  stz clockMinute
  stz clockSecond

  ldx #$0000
  lda #' '
@clearDisplay:
  sta clockDisplayText, x
  inx
  cpx #(TERMINAL_COLUMNS - 7)
  bne @clearDisplay

  lda #'-'
  sta clockDisplayText + 0
  sta clockDisplayText + 1
  sta clockDisplayText + 2
  sta clockDisplayText + 3
  sta clockDisplayText + 4
  sta clockDisplayText + 5
  sta clockDisplayText + 6
  sta clockDisplayText + 7
  sta clockDisplayText + 8
  sta clockDisplayText + 9
  sta clockDisplayText + 11
  sta clockDisplayText + 12
  sta clockDisplayText + 14
  sta clockDisplayText + 15
  sta clockDisplayText + 17
  sta clockDisplayText + 18
  lda #' '
  sta clockDisplayText + 4
  sta clockDisplayText + 7
  lda #':'
  sta clockDisplayText + 13
  sta clockDisplayText + 16
  lda #'J'
  sta clockDisplayText + 20
  lda #'S'
  sta clockDisplayText + 21
  lda #'T'
  sta clockDisplayText + 22

  rep #$20
  .a16
  plx
  plb
  pla
  rts
.endproc

; Commit a generic Unix timestamp.
; Input (all 16-bit): A=seconds low, X=seconds high,
; Y=upper 16 bits of the binary-fraction field. The lower fraction bits are
; intentionally zeroed; this retains sub-millisecond precision while keeping
; the protocol-independent clock ABI compact.
.proc clockSetUnixTime
  .a16
  .i16

  sta clockUnixSeconds
  stx clockUnixSeconds + 2
  stz clockSubsecond
  sty clockSubsecond + 2
  lda frameCounter
  sta clockLastFrame

  sep #$20
  .a8
  lda #$01
  sta clockValid
  rep #$20
  .a16
  jsr @decomposeJst
  jsr clockFormatDisplay
  rts

; Convert UTC Unix seconds to the supported JST calendar range
; (1970-01-01 through the 32-bit Unix rollover in 2106).
@decomposeJst:
  lda clockUnixSeconds
  clc
  adc #(CLOCK_JST_OFFSET_SECONDS & $ffff)
  sta clockConversionRemaining
  lda clockUnixSeconds + 2
  adc #((CLOCK_JST_OFFSET_SECONDS >> 16) & $ffff)
  sta clockConversionRemaining + 2

  lda #1970
  sta clockYear
@yearLoop:
  jsr clockIsLeapYear
  bcc @commonYear
  clockSubtractIfAtLeast CLOCK_LEAP_YEAR_SECONDS, @yearsDone
  inc clockYear
  bra @yearLoop
@commonYear:
  clockSubtractIfAtLeast CLOCK_COMMON_YEAR_SECONDS, @yearsDone
  inc clockYear
  bra @yearLoop
@yearsDone:

  sep #$20
  .a8
  lda #$01
  sta clockMonth
  rep #$20
  .a16
@monthLoop:
  sep #$20
  .a8
  lda clockMonth
  cmp #$02
  beq @february
  cmp #$04
  beq @thirtyDayMonth
  cmp #$06
  beq @thirtyDayMonth
  cmp #$09
  beq @thirtyDayMonth
  cmp #$0b
  beq @thirtyDayMonth
  rep #$20
  .a16
  clockSubtractIfAtLeast CLOCK_31_DAY_MONTH_SECONDS, @monthsDone
  jmp @advanceMonth
@thirtyDayMonth:
  rep #$20
  .a16
  clockSubtractIfAtLeast CLOCK_30_DAY_MONTH_SECONDS, @monthsDone
  jmp @advanceMonth
@february:
  rep #$20
  .a16
  jsr clockIsLeapYear
  bcc @commonFebruary
  clockSubtractIfAtLeast CLOCK_29_DAY_MONTH_SECONDS, @monthsDone
  jmp @advanceMonth
@commonFebruary:
  clockSubtractIfAtLeast CLOCK_28_DAY_MONTH_SECONDS, @monthsDone
@advanceMonth:
  sep #$20
  .a8
  inc clockMonth
  rep #$20
  .a16
  jmp @monthLoop
@monthsDone:

  sep #$20
  .a8
  lda #$01
  sta clockDay
  rep #$20
  .a16
@dayLoop:
  clockSubtractIfAtLeast CLOCK_DAY_SECONDS, @daysDone
  sep #$20
  .a8
  inc clockDay
  rep #$20
  .a16
  bra @dayLoop
@daysDone:

  sep #$20
  .a8
  stz clockHour
  rep #$20
  .a16
@hourLoop:
  clockSubtractIfAtLeast CLOCK_HOUR_SECONDS, @hoursDone
  sep #$20
  .a8
  inc clockHour
  rep #$20
  .a16
  bra @hourLoop
@hoursDone:

  sep #$20
  .a8
  stz clockMinute
  rep #$20
  .a16
@minuteLoop:
  clockSubtractIfAtLeast CLOCK_MINUTE_SECONDS, @minutesDone
  sep #$20
  .a8
  inc clockMinute
  rep #$20
  .a16
  bra @minuteLoop
@minutesDone:
  sep #$20
  .a8
  lda clockConversionRemaining
  sta clockSecond
  rep #$20
  .a16
  rts

; Carry set for leap years. The 32-bit Unix range ends in 2106, so only 2000
; and 2100 need explicit Gregorian century handling.
clockIsLeapYear:
  lda clockYear
  cmp #2000
  beq @leap
  cmp #2100
  beq @notLeap
  and #$0003
  beq @leap
@notLeap:
  clc
  rts
@leap:
  sec
  rts

clockFormatDisplay:
  phx
  ldx #$0000
  lda clockYear
  jsr @writeYear

  sep #$20
  .a8
  lda #'-'
  sta clockDisplayText + 4
  sta clockDisplayText + 7
  lda #' '
  sta clockDisplayText + 10
  sta clockDisplayText + 19
  lda #':'
  sta clockDisplayText + 13
  sta clockDisplayText + 16
  lda #'J'
  sta clockDisplayText + 20
  lda #'S'
  sta clockDisplayText + 21
  lda #'T'
  sta clockDisplayText + 22

  ldx #$0005
  lda clockMonth
  jsr @writeTwoDigits
  ldx #$0008
  lda clockDay
  jsr @writeTwoDigits
  ldx #$000b
  lda clockHour
  jsr @writeTwoDigits
  ldx #$000e
  lda clockMinute
  jsr @writeTwoDigits
  ldx #$0011
  lda clockSecond
  jsr @writeTwoDigits
  rep #$20
  .a16
  plx
  rts

@writeYear:
  .a16
  ldy #'0'
@thousands:
  cmp #1000
  bcc @thousandsDone
  sec
  sbc #1000
  iny
  bra @thousands
@thousandsDone:
  pha
  sep #$20
  .a8
  tya
  sta clockDisplayText, x
  inx
  rep #$20
  .a16
  pla
  ldy #'0'
@hundreds:
  cmp #100
  bcc @hundredsDone
  sec
  sbc #100
  iny
  bra @hundreds
@hundredsDone:
  pha
  sep #$20
  .a8
  tya
  sta clockDisplayText, x
  inx
  rep #$20
  .a16
  pla
  ldy #'0'
@tens:
  cmp #10
  bcc @tensDone
  sec
  sbc #10
  iny
  bra @tens
@tensDone:
  pha
  sep #$20
  .a8
  tya
  sta clockDisplayText, x
  inx
  rep #$20
  .a16
  pla
  sep #$20
  .a8
  clc
  adc #'0'
  sta clockDisplayText, x
  rep #$20
  .a16
  rts

@writeTwoDigits:
  .a8
  phy
  ldy #'0'
@twoDigitTens:
  cmp #10
  bcc @twoDigitTensDone
  sec
  sbc #10
  iny
  bra @twoDigitTens
@twoDigitTensDone:
  pha
  tya
  sta clockDisplayText, x
  inx
  pla
  clc
  adc #'0'
  sta clockDisplayText, x
  ply
  rts
.endproc

; Advance the synchronized clock by however many VBlank frames elapsed since
; the previous main-loop poll.
.proc clockPoll
  .a16
  .i16

  pha
  phb
  phx
  phy
  setDBR $7e

  lda frameCounter
  sec
  sbc clockLastFrame
  beq @done
  tax
  lda frameCounter
  sta clockLastFrame

  sep #$20
  .a8
  lda clockValid
  beq @done16
  rep #$20
  .a16
  jsr clockAdvanceFrames
  bra @done

@done16:
  rep #$20
  .a16
@done:
  ply
  plx
  plb
  pla
  rts
.endproc

; Advance an already synchronized clock by X nominal NTSC frames. This is a
; separate entry point so the permanent self-test can exercise second-boundary
; behavior without racing the live NMI frame counter.
.proc clockAdvanceFrames
  .a16
  .i16
@frameLoop:
  lda clockSubsecond
  clc
  adc #CLOCK_NTSC_FRAME_FRACTION_LOW
  sta clockSubsecond
  lda clockSubsecond + 2
  adc #CLOCK_NTSC_FRAME_FRACTION_HIGH
  sta clockSubsecond + 2
  bcc @nextFrame

  inc clockUnixSeconds
  bne :+
  inc clockUnixSeconds + 2
:
  jsr clockIncrementCalendar
  jsr clockSetUnixTime::clockFormatDisplay

@nextFrame:
  dex
  bne @frameLoop
  rts
.endproc

.proc clockIncrementCalendar
  .a16
  .i16
  sep #$20
  .a8
  inc clockSecond
  lda clockSecond
  cmp #60
  bcc @calendarDone
  stz clockSecond
  inc clockMinute
  lda clockMinute
  cmp #60
  bcc @calendarDone
  stz clockMinute
  inc clockHour
  lda clockHour
  cmp #24
  bcc @calendarDone
  stz clockHour
  inc clockDay
  jsr clockDaysInMonth
  cmp clockDay
  bcs @calendarDone
  lda #$01
  sta clockDay
  inc clockMonth
  lda clockMonth
  cmp #13
  bcc @calendarDone
  lda #$01
  sta clockMonth
  rep #$20
  .a16
  inc clockYear
  sep #$20
  .a8
@calendarDone:
  rep #$20
  .a16
  rts
.endproc

.proc clockDaysInMonth
  .a8
  .i16
  lda clockMonth
  cmp #$02
  beq @calendarFebruary
  cmp #$04
  beq @calendarThirty
  cmp #$06
  beq @calendarThirty
  cmp #$09
  beq @calendarThirty
  cmp #$0b
  beq @calendarThirty
  lda #31
  rts
@calendarThirty:
  lda #30
  rts
@calendarFebruary:
  rep #$20
  .a16
  jsr clockSetUnixTime::clockIsLeapYear
  sep #$20
  .a8
  bcc @calendarFebruaryCommon
  lda #29
  rts
@calendarFebruaryCommon:
  lda #28
  rts
.endproc
