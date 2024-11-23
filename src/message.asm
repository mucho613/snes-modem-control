.segment "STARTUP"

.export startup
startup:
.byte "Modem control test - @mucho613", $0a, "--------------------------------", $0a, $00

.export startModemConfiguration
startModemConfiguration:
.byte "Start modem configuration.", $0a, $00

.export dialing
dialing:
.byte "Dialing...", $0a, $00

.export pleaseConnectModemMessage
pleaseConnectModemMessage:
.byte "Please connect NDM24 modem to controller port 2.", $0a, $00
