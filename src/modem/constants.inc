; Human-maintained protocol helpers live here. Numeric values shared with the
; Rust tools and documentation are generated from spec/ndm24.toml.
.include "generated.inc"

MODEM_TRACE_RECORD_SEQUENCE = $00
MODEM_TRACE_RECORD_FRAME = $04
MODEM_TRACE_RECORD_KIND = $08
MODEM_TRACE_RECORD_STATE = $09
MODEM_TRACE_RECORD_REASON = $0a
MODEM_TRACE_RECORD_FLAGS = $0b
MODEM_TRACE_RECORD_DATA = $0c
MODEM_TRACE_RECORD_STATUS = $0e

MODEM_ERROR_NONE = $00
MODEM_ERROR_PROBE_TIMEOUT = $01
MODEM_ERROR_PROBE_REJECTED = $02

MODEM_SESSION_RESULT_NONE = $00
MODEM_SESSION_RESULT_OK = $01
MODEM_SESSION_RESULT_ERROR = $02
MODEM_SESSION_RESULT_CONNECT = $03
MODEM_SESSION_RESULT_NO_CARRIER = $04
MODEM_SESSION_RESULT_BUSY = $05
MODEM_SESSION_RESULT_NO_DIALTONE = $06

.macro modemIncrement32 address
  .local done
  rep #$20
  .a16
  inc address
  bne done
  inc address + 2
done:
  sep #$20
  .a8
.endmacro
