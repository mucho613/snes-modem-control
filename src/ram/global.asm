.bss

.export frameCounter
frameCounter: .res $4

.export controller1Input, controller1InputPrev
controller1Input: .res $4
controller1InputPrev: .res $4

.export controller2InputData1, controller2InputData2
controller2InputData1: .res $2
controller2InputData2: .res $2

.export terminalTextPointer
terminalTextPointer: .res $2

.export terminalTextBuffer
terminalTextBuffer: .res $100

.export modemReceiveBufferCount
modemReceiveBufferCount: .res $1

.export modemReceiveBuffer
modemReceiveBuffer: .res $40

.export modemTransmitBufferCount
modemTransmitBufferCount: .res $1

.export modemTransmitBuffer
modemTransmitBuffer: .res $40
