.segment "STARTUP"

.export startup
startup:
.byte "modem-control-test", $0a, "--------------------------------", $0a, $00

.export executeModemSettings
executeModemSettings:
.byte "Execute modem settings.", $0a, $00

.export pleaseConnectModemMessage
pleaseConnectModemMessage:
.byte "Please connect NDM24 modem to controller port 2.", $0a, $00
