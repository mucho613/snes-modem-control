; Build-time application-status selection point.
;
; The UI imports only applicationStatusInitialize/applicationStatusPoll.
; Keep protocol-specific state mapping in an adapter included here so adding
; another adapter does not create duplicate exports through xtask's recursive
; collection of every .asm source.

.include "../modem/generated.inc"
.include "../ppp/constants.inc"

; Replace this include to select another application at build time.
.include "ntp.inc"
