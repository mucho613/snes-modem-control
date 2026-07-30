.macro m16
  rep #$20
  .a16
.endmacro

.macro m8
  sep #$20
  .a8
.endmacro

.macro i16
  rep #$10
  .i16
.endmacro

.macro i8
  sep #$10
  .i8
.endmacro

.macro mi16
  rep #$30
  .a16
  .i16
.endmacro

.macro mi8
  sep #$30
  .a8
  .i8
.endmacro

; Declaration-only synchronization at a control-flow merge. The Rust width
; lint proves that every incoming runtime state matches the asserted widths.
.macro assert_m8_i8
  .a8
  .i8
.endmacro

.macro assert_m8_i16
  .a8
  .i16
.endmacro

.macro assert_m16_i8
  .a16
  .i8
.endmacro

.macro assert_m16_i16
  .a16
  .i16
.endmacro

; PLP changes the runtime M/X flags without informing ca65. These wrappers
; restore the assembler declarations and are checked against the width state
; saved by PHP.
.macro plp_m8_i8
  plp
  .a8
  .i8
.endmacro

.macro plp_m8_i16
  plp
  .a8
  .i16
.endmacro

.macro plp_m16_i8
  plp
  .a16
  .i8
.endmacro

.macro plp_m16_i16
  plp
  .a16
  .i16
.endmacro

.macro inc32 address
  m16

  inc address
  bne @end
  inc address + 2
  @end:
.endmacro

.macro setDBR bank
  pea bank << 8
  plb
  plb
.endmacro

.macro setDP address
  pea address
  pld
.endmacro

; NMITIMEN is write-only, so callers keep its current value in WRAM. These
; macros require 8-bit A and a DBR that can access the shadow. NMITIMEN and
; HVBJOY are outside the $4000 direct-page window, so DBR is temporarily
; changed to bank 0 for the absolute hardware access.
;
; Enabling NMI while VBlank is already active can immediately raise another
; NMI. Wait for active display before both transitions so the bit-bang starts
; after the current VBlank and restoring $80 cannot create an NMI storm. The
; saved byte on the stack makes nesting restore the exact prior state.
.macro suspendNmi shadow
  lda shadow
  pha
  phb
  setDBR $00
:
  lda HVBJOY
  bmi :-
  stz NMITIMEN
  plb
  stz shadow
.endmacro

.macro restoreNmi shadow
  phb
  setDBR $00
:
  lda HVBJOY
  bmi :-
  plb
  pla
  sta shadow
  phb
  setDBR $00
  sta NMITIMEN
  plb
.endmacro
