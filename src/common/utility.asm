.macro inc32 address
  .a16
  .i16

  inc address
  bne @end
  inc address + 2
  @end:
.endmacro

.macro add operand
  clc
  adc operand
.endmacro

.macro sub operand
  sec
  sbc operand
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
