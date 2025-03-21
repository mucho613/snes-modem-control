.segment "STARTUP"

; BG の表示 / 非表示を切り替えるテーブル
.export bgEnableHdmaTable
bgEnableHdmaTable:
.byte 46, $00, $00
.byte 66, $01, $01
.byte 66, $01, $01
.byte 1, $00, $00
.byte 0 ; End of table
