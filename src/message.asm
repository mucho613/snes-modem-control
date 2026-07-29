.code

.export startup
startup:
.byte "modem-control-test", $0a, "--------------------------------", $0a, $00

; Generated font specimen and embedded provenance. The attribution label is
; intentionally linked into every ROM even though only the font-test ROM
; displays the short Public Domain line contained in fontTestScreen.
.include "./terminal/generated-font.inc"
