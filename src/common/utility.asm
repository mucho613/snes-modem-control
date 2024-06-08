.macro inc32 address
  .a16
  .i16

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
