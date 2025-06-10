.macro a16
  rep #$20
  .a16
.endmacro

.macro a8
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

.macro ai16
  rep #$30
  .a16
  .i16
.endmacro

.macro ai8
  sep #$30
  .a8
  .i8
.endmacro

.macro inc32 address
  rep #$20
  .a16

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
