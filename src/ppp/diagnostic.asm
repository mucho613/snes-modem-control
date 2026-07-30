.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import pppDiagnosticMagic, pppDiagnosticVersion, pppDiagnosticSize
.import pppSnapshotSequence, pppSnapshotDepth

.export pppDiagnosticInitialize, pppSnapshotBegin, pppSnapshotEnd
.export pppSnapshotBeginI8, pppSnapshotEndI8

.proc pppDiagnosticInitialize
  .a8
  .i16

  phb
  setDBR $7e
  lda #PPP_DIAGNOSTIC_MAGIC_0
  sta pppDiagnosticMagic
  lda #PPP_DIAGNOSTIC_MAGIC_1
  sta pppDiagnosticMagic + 1
  lda #PPP_DIAGNOSTIC_MAGIC_2
  sta pppDiagnosticMagic + 2
  lda #PPP_DIAGNOSTIC_MAGIC_3
  sta pppDiagnosticMagic + 3

  m16
  lda #PPP_DIAGNOSTIC_VERSION
  sta pppDiagnosticVersion
  lda #PPP_DIAGNOSTIC_SIZE
  sta pppDiagnosticSize
  stz pppSnapshotSequence
  stz pppSnapshotSequence + 2
  m8
  stz pppSnapshotDepth
  plb
  rts
.endproc

.proc pppSnapshotBegin
  .a8
  .i16

  pha
  lda pppSnapshotDepth
  bne nested
  pppIncrement32 pppSnapshotSequence
nested:
  inc pppSnapshotDepth
  pla
  rts
.endproc

.proc pppSnapshotEnd
  .a8
  .i16

  pha
  dec pppSnapshotDepth
  bne nested
  pppIncrement32 pppSnapshotSequence
nested:
  pla
  rts
.endproc

.proc pppSnapshotBeginI8
  .a8
  .i8

  pha
  lda pppSnapshotDepth
  bne nested
  pppIncrement32 pppSnapshotSequence
nested:
  inc pppSnapshotDepth
  pla
  rts
.endproc

.proc pppSnapshotEndI8
  .a8
  .i8

  pha
  dec pppSnapshotDepth
  bne nested
  pppIncrement32 pppSnapshotSequence
nested:
  pla
  rts
.endproc
