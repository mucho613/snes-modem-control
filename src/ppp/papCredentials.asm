.include "../macro/utility.asm"
.include "../modem/generated.inc"
.include "constants.inc"

.import modemMailboxArguments
.import pppSnapshotBeginLong, pppSnapshotEndLong
.import pppPapCredentialFlags, pppPapPeerIdLength, pppPapPasswordLength
.import pppPapPeerId, pppPapPassword
.import pppTransmitBuffer

.export pppPapCredentialsInitialize
.export pppPapCredentialsClear, pppPapCredentialsClearSensitive
.export pppPapCredentialSetPeerId, pppPapCredentialSetPassword
.export pppPapCredentialsReady
.export pppPapCredentialsRunSelfTest
.export pppPapScrubTransmitBuffer

.segment "BANK1_CODE"

; Install the public closed-test fixture. Real credentials replace this only
; after an explicit clear command enters transient mode.
.proc pppPapCredentialsInitialize
  .a8
  .i16

  phb
  setDBR $7e
  jsl pppSnapshotBeginLong
  jsr @wipeBuffers
  lda #PPP_PAP_PEER_ID_LENGTH
  sta pppPapPeerIdLength
  lda #PPP_PAP_PASSWORD_LENGTH
  sta pppPapPasswordLength
  lda #(PPP_PAP_CREDENTIAL_FLAG_PEER_ID | PPP_PAP_CREDENTIAL_FLAG_PASSWORD)
  sta pppPapCredentialFlags

  lda #'n'
  sta pppPapPeerId + 0
  lda #'d'
  sta pppPapPeerId + 1
  lda #'m'
  sta pppPapPeerId + 2
  lda #'2'
  sta pppPapPeerId + 3
  lda #'4'
  sta pppPapPeerId + 4

  lda #'n'
  sta pppPapPassword + 0
  lda #'d'
  sta pppPapPassword + 1
  lda #'m'
  sta pppPapPassword + 2
  lda #'2'
  sta pppPapPassword + 3
  lda #'4'
  sta pppPapPassword + 4
  lda #'-'
  sta pppPapPassword + 5
  lda #'t'
  sta pppPapPassword + 6
  lda #'e'
  sta pppPapPassword + 7
  lda #'s'
  sta pppPapPassword + 8
  lda #'t'
  sta pppPapPassword + 9
  jsl pppSnapshotEndLong
  plb
  rtl

@wipeBuffers:
  assert_m8_i16
  ldx #$0000
  lda #$00
@wipePeerId:
  sta pppPapPeerId, x
  inx
  cpx #PPP_PAP_MAXIMUM_PEER_ID_LENGTH
  bne @wipePeerId
  ldx #$0000
@wipePassword:
  sta pppPapPassword, x
  inx
  cpx #PPP_PAP_MAXIMUM_PASSWORD_LENGTH
  bne @wipePassword
  stz pppPapPeerIdLength
  stz pppPapPasswordLength
  rts
.endproc

; Enter transient mode and erase both staged fields. This must precede the two
; set commands so an interrupted upload can never combine old and new data.
.proc pppPapCredentialsClear
  .a8
  .i16

  phb
  setDBR $7e
  jsl pppSnapshotBeginLong
  jsr @wipeAll
  lda #PPP_PAP_CREDENTIAL_FLAG_TRANSIENT
  sta pppPapCredentialFlags
  jsl pppSnapshotEndLong
  jsr @wipeMailbox
  plb
  clc
  rtl

@wipeAll:
  assert_m8_i16
  ldx #$0000
  lda #$00
@peer:
  sta pppPapPeerId, x
  inx
  cpx #PPP_PAP_MAXIMUM_PEER_ID_LENGTH
  bne @peer
  ldx #$0000
@password:
  sta pppPapPassword, x
  inx
  cpx #PPP_PAP_MAXIMUM_PASSWORD_LENGTH
  bne @password
  stz pppPapPeerIdLength
  stz pppPapPasswordLength
  rts

@wipeMailbox:
  assert_m8_i16
  ldx #$0000
  lda #$00
:
  sta modemMailboxArguments, x
  inx
  cpx #MODEM_MAILBOX_ARGUMENT_SIZE
  bne :-
  rts
.endproc

; Erase real credentials and their presence bits on every terminal path.
; The closed-test fixture is intentionally retained for repeatable lab tests.
.proc pppPapCredentialsClearSensitive
  .a8
  .i16

  phb
  setDBR $7e
  lda pppPapCredentialFlags
  and #PPP_PAP_CREDENTIAL_FLAG_TRANSIENT
  beq @done
  jsl pppSnapshotBeginLong
  ldx #$0000
  lda #$00
@peer:
  sta pppPapPeerId, x
  inx
  cpx #PPP_PAP_MAXIMUM_PEER_ID_LENGTH
  bne @peer
  ldx #$0000
@password:
  sta pppPapPassword, x
  inx
  cpx #PPP_PAP_MAXIMUM_PASSWORD_LENGTH
  bne @password
  stz pppPapPeerIdLength
  stz pppPapPasswordLength
  lda #PPP_PAP_CREDENTIAL_FLAG_TRANSIENT
  sta pppPapCredentialFlags
  jsl pppSnapshotEndLong
@done:
  plb
  rtl
.endproc

; Arguments: [length, bytes...]. Carry set returns an error code in A.
.proc pppPapCredentialSetPeerId
  .a8
  .i16

  phb
  setDBR $7e
  lda pppPapCredentialFlags
  and #PPP_PAP_CREDENTIAL_FLAG_TRANSIENT
  bne :+
  lda #PPP_PAP_CREDENTIAL_ERROR_NOT_CLEARED
  jmp @failed
:
  lda modemMailboxArguments
  cmp #PPP_PAP_MAXIMUM_PEER_ID_LENGTH
  beq :+
  lda #PPP_PAP_CREDENTIAL_ERROR_INVALID_LENGTH
  jmp @failed
:
  jsl pppSnapshotBeginLong
  sta pppPapPeerIdLength
  tax
  ldy #$0000
@copy:
  lda modemMailboxArguments + 1, y
  sta pppPapPeerId, y
  iny
  dex
  bne @copy
  lda pppPapCredentialFlags
  ora #PPP_PAP_CREDENTIAL_FLAG_PEER_ID
  sta pppPapCredentialFlags
  jsl pppSnapshotEndLong
  jsr @wipeMailbox
  plb
  clc
  rtl

@failed:
  pha
  jsl pppPapCredentialsClear
  pla
  plb
  sec
  rtl

@wipeMailbox:
  ldx #$0000
  lda #$00
:
  sta modemMailboxArguments, x
  inx
  cpx #MODEM_MAILBOX_ARGUMENT_SIZE
  bne :-
  rts
.endproc

; Arguments: [length, bytes...]. Carry set returns an error code in A.
.proc pppPapCredentialSetPassword
  .a8
  .i16

  phb
  setDBR $7e
  lda pppPapCredentialFlags
  and #PPP_PAP_CREDENTIAL_FLAG_TRANSIENT
  bne :+
  lda #PPP_PAP_CREDENTIAL_ERROR_NOT_CLEARED
  jmp @failed
:
  lda modemMailboxArguments
  cmp #PPP_PAP_MINIMUM_PASSWORD_LENGTH
  bcc @invalidLength
  cmp #(PPP_PAP_MAXIMUM_PASSWORD_LENGTH + 1)
  bcc :+
@invalidLength:
  lda #PPP_PAP_CREDENTIAL_ERROR_INVALID_LENGTH
  jmp @failed
:
  jsl pppSnapshotBeginLong
  sta pppPapPasswordLength
  tax
  ldy #$0000
@copy:
  lda modemMailboxArguments + 1, y
  sta pppPapPassword, y
  iny
  dex
  bne @copy
  lda pppPapCredentialFlags
  ora #PPP_PAP_CREDENTIAL_FLAG_PASSWORD
  sta pppPapCredentialFlags
  jsl pppSnapshotEndLong
  jsr @wipeMailbox
  plb
  clc
  rtl

@failed:
  pha
  jsl pppPapCredentialsClear
  pla
  plb
  sec
  rtl

@wipeMailbox:
  ldx #$0000
  lda #$00
:
  sta modemMailboxArguments, x
  inx
  cpx #MODEM_MAILBOX_ARGUMENT_SIZE
  bne :-
  rts
.endproc

; Carry clear means both credential fields are present.
.proc pppPapCredentialsReady
  .a8
  .i16

  lda pppPapCredentialFlags
  and #PPP_PAP_CREDENTIAL_REQUIRED_FLAGS
  cmp #PPP_PAP_CREDENTIAL_REQUIRED_FLAGS
  beq @ready
  sec
  rtl
@ready:
  clc
  rtl
.endproc

; Erase the PAP Peer-ID and Password source bytes as soon as the shared
; encoder no longer needs them. Header fields remain available for diagnostics.
.proc pppPapScrubTransmitBuffer
  .a8
  .i16

  phb
  setDBR $7e
  lda pppTransmitBuffer + 2
  cmp #$c0
  bne @done
  lda pppTransmitBuffer + 3
  cmp #$23
  bne @done
  ldx #PPP_UNCOMPRESSED_HEADER_LENGTH + PPP_PAP_HEADER_LENGTH
  lda #$00
:
  sta pppTransmitBuffer, x
  inx
  cpx #PPP_PAP_MAXIMUM_TRANSMIT_FRAME_LENGTH
  bne :-
@done:
  plb
  rtl
.endproc

; Closed fixture: validates two-stage upload, mailbox scrubbing, and teardown.
.proc pppPapCredentialsRunSelfTest
  .a8
  .i16

  jsl pppPapCredentialsClear
  lda #PPP_PAP_MAXIMUM_PEER_ID_LENGTH
  sta modemMailboxArguments
  ldx #$0000
@fillId:
  txa
  ora #$40
  sta modemMailboxArguments + 1, x
  inx
  cpx #PPP_PAP_MAXIMUM_PEER_ID_LENGTH
  bne @fillId
  jsl pppPapCredentialSetPeerId
  bcs @failed

  lda #PPP_PAP_MINIMUM_PASSWORD_LENGTH
  sta modemMailboxArguments
  ldx #$0000
@fillPassword:
  txa
  ora #$60
  sta modemMailboxArguments + 1, x
  inx
  cpx #PPP_PAP_MINIMUM_PASSWORD_LENGTH
  bne @fillPassword
  jsl pppPapCredentialSetPassword
  bcs @failed
  jsl pppPapCredentialsReady
  bcs @failed

  ldx #$0000
@mailboxZero:
  lda modemMailboxArguments, x
  bne @failed
  inx
  cpx #MODEM_MAILBOX_ARGUMENT_SIZE
  bne @mailboxZero

  jsl pppPapCredentialsClearSensitive
  lda pppPapPeerIdLength
  ora pppPapPasswordLength
  bne @failed
  lda pppPapCredentialFlags
  cmp #PPP_PAP_CREDENTIAL_FLAG_TRANSIENT
  bne @failed

  jsl pppPapCredentialsInitialize
  lda #$00
  clc
  rtl

@failed:
  jsl pppPapCredentialsInitialize
  lda #$69
  sec
  rtl
.endproc
