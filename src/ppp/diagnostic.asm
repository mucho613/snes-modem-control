.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.code

.import pppDiagnosticMagic, pppDiagnosticVersion, pppDiagnosticSize
.import pppSnapshotSequence, pppSnapshotDepth

.export pppDiagnosticInitialize, pppSnapshotBegin, pppSnapshotEnd

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

  rep #$20
  .a16
  lda #PPP_DIAGNOSTIC_VERSION
  sta pppDiagnosticVersion
  lda #PPP_DIAGNOSTIC_SIZE
  sta pppDiagnosticSize
  stz pppSnapshotSequence
  stz pppSnapshotSequence + 2
  sep #$20
  .a8
  stz pppSnapshotDepth
  plb
  rts
.endproc

.proc pppSnapshotBegin
  .a8

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

  pha
  dec pppSnapshotDepth
  bne nested
  pppIncrement32 pppSnapshotSequence
nested:
  pla
  rts
.endproc
