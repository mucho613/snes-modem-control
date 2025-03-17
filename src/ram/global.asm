.bss

.export frameCounter
frameCounter: .res $4

.export terminalScrollLineNumber
terminalScrollLineNumber: .res $1

.export bg1YScrollPos
bg1YScrollPos: .res $2

.export bufW12SEL
bufW12SEL: .res $1

.export bufWH0
bufWH0: .res $1

.export bufWH1
bufWH1: .res $1

.export controller1Input, controller1InputPrev, controller1InputPulse
controller1Input: .res $4
controller1InputPrev: .res $4
controller1InputPulse: .res $4

.export controller2InputData1, controller2InputData2
controller2InputData1: .res $2
controller2InputData2: .res $2

.export terminalTextPointer
terminalTextPointer: .res $2

.export terminalTextWriteBuffer ; Store texts that will be written in terminal
terminalTextWriteBuffer: .res $100

.export terminalTextBuffer ; Store all of texts in terminal
terminalTextBuffer: .res 80 * 28 ; 80 columns, 28 rows

.export modemReceiveBufferCount
modemReceiveBufferCount: .res $1

.export modemReceiveBuffer
modemReceiveBuffer: .res $40

.export modemTransmitBufferCount
modemTransmitBufferCount: .res $1

.export modemTransmitBuffer
modemTransmitBuffer: .res $40
