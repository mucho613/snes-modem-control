.bss

.export frameCounter
frameCounter: .res $4

.export controller1Input, controller1InputPrev, controller2Input, controller2InputPrev
controller1Input: .res $4
controller1InputPrev: .res $4
controller2Input: .res $4
controller2InputPrev: .res $4

.export terminalTextPointer
terminalTextPointer: .res $2

.export terminalTextBuffer
terminalTextBuffer: .res $100
