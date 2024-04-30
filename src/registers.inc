; Forced blanking (F), screen brightness (B).
; Type: W8
; Bits: F... BBBB
.define INIDISP $2100

; OBJ sprite size (S), name secondary select (N), name base address (B).
; Type: W8
; Bits: SSSN NbBB
.define OBJSEL $2101

; OAM word address (A).
; Type: W16
; Bits: AAAA AAAA
.define OAMADDL $2102

; Priority rotation (P), address high bit (B).
; Bits: P... ...B
.define OAMADDH $2103

; OAM data write byte (2x for word) (D), increments OAMADD byte.
; Type: W8x2
; Bits: DDDD DDDD
.define OAMDATA $2104

; Tilemap tile size (#), BG3 priority (P), BG mode (M).
; Type: W8
; Bits: 4321 PMMM
.define BGMODE $2105

; Mosaic size (S), mosaic BG enable (#).
; Type: W8
; Bits: SSSS 4321
.define MOSAIC $2106

; Tilemap VRAM address (A), vertical tilemap count (Y), horizontal tilemap count (X).
; Type: W8
; Bits: AAAA AAYX
.define BG1SC $2107
.define BG2SC $2108
.define BG3SC $2109
.define BG4SC $210A

; BG2 CHR base address (B), BG1 CHR base address (A).
; Type: W8;
; Bits: BBBB AAAA
.define BG12NBA $210B

; BG4 CHR base address (D), BG3 CHR base address (C).
; Type: W8
; Bits: DDDD CCCC
.define BG34NBA $210C

; Mode 7 horizontal scroll (X).
; Type: W8x2
; Bits: ...x xxxx xxxx xxxx
.define M7HOFS $210D

; Mode 7 vertical scroll (Y).
; Type: W8x2
; Bits: ...y yyyy yyyy yyyy
.define M7VOFS $210E

; BG1 horizontal scroll (X).
; Type: W8x2
; Bits: .... ..XX XXXX XXXX
.define BG1HOFS $210D

; BG1 vertical scroll (Y).
; Type: W8x2
; Bits: .... ..YY YYYY YYYY
.define BG1VOFS $210E

; BG2 horizontal scroll (X).
; Type: W8x2
; Bits: .... ..XX XXXX XXXX
.define BG2HOFS $210F

; BG2 vertical scroll (Y).
; Type: W8x2
; Bits: .... ..YY YYYY YYYY
.define BG2VOFS $2110

; BG3 horizontal scroll (X).
; Type: W8x2
; Bits: .... ..XX XXXX XXXX
.define BG3HOFS $2111

; BG3 vertical scroll (Y).
; Type: W8x2
; Bits: .... ..YY YYYY YYYY
.define BG3VOFS $2112

; BG4 horizontal scroll (X).
; Type: W8x2
; Bits: .... ..XX XXXX XXXX
.define BG4HOFS $2113

; BG4 vertical scroll (Y).
; Type: W8x2
; Bits: .... ..YY YYYY YYYY
.define BG4VOFS $2114

; VRAM address increment mode (M), remapping (R), increment size (I).
; Type: W8
; Bits: M... RRII
.define VMAIN $2115

; VRAM word address.
; Type: W16
; Bits: LLLL LLLL
.define VMADDL $2116
; Bits: HHHH HHHH
.define VMADDH $2117

; VRAM data write. Increments VMADD after write according to VMAIN setting.
; Type: W16
; Bits: LLLL LLLL
.define VMDATAL $2118
; Bits: HHHH HHHH
.define VMDATAH $2119

; Mode 7 tilemap repeat (R), fill (F), flip vertical (Y), flip horizontal (X).
; Type: W8
; Bits: RF.. ..YX
.define M7SEL $211A

; Mode 7 matrix A or signed 16-bit multiplication factor.
; Type: W8x2
; Bits: DDDD DDDD dddd dddd
.define M7A $211B

; Mode 7 matrix B or signed 8-bit multiplication factor.
; Type: W8x2
; Bits: DDDD DDDD dddd dddd
.define M7B $211C

; Mode 7 matrix C.
; Type: W8x2
; Bits: DDDD DDDD dddd dddd
.define M7C $211D

; Mode 7 matrix D.
; Type: W8x2
; Bits: DDDD DDDD dddd dddd
.define M7D $211E

; Mode 7 center X.
; Type: W8x2
; Bits: ...X XXXX XXXX XXXX
.define M7X $211F

; Mode 7 center Y.
; Type: W8x2
; Bits: ...Y YYYY YYYY YYYY
.define M7Y $2120

; CGRAM word address.
; Type: W8
; Bits: AAAA AAAA
.define CGADD $2121

; CGRAM data write. increments CGADD byte address after each write.
; Type: W8x2
; Bits: .BBB BBGG GGGR RRRR
.define CGDATA $2122

; Enable (ABCD) and Invert (abcd) windows for BG1 (AB) and BG2 (CD).
; Type: W8
; Bits: DdCc BbAa
.define W12SEL $2123

; Enable (EFGH) and Invert (efgh) windows for BG3 (EF) and BG4 (GH).
; Type: W8
; Bits: HhGg FfEe
.define W34SEL $2124

; Enable (IJKL) and Invert (ijkl) windows for OBJ (IJ) and color (KL).
; Type: W8
; Bits: LlKk JjIi
.define WOBJSEL $2125

; Window 1 left position.
; Type: W8
; Bits: LLLL LLLL
.define WH0 $2126

; Window 1 right position.
; Type: W8
; Bits: RRRR RRRR
.define WH1 $2127

; Window 2 left position.
; Type: W8
; Bits: LLLL LLLL
.define WH2 $2128

; Window 2 right position.
; Type: W8
; Bits: RRRR RRRR
.define WH3 $2129

; Window mask logic for BG layers (00=OR, 01=AND, 10=XOR, 11=XNOR).
; Type: W8
; Bits: 4433 2211
.define WBGLOG $212A

; Window mask logic for OBJ (O) and color (C) (00=OR, 01=AND, 10=XOR, 11=XNOR).
; Type: W8
; Bits: .... CCOO
.define WOBJLOG $212B

; Main screen layer enable (PPU registers#).
; Type: W8
; Bits: ...O 4321
.define TM $212C

; Sub screen layer enable (PPU registers#).
; Type: W8
; Bits: ...O 4321
.define TS $212D

; Main screen layer window enable.
; Type: W8
; Bits: ...O 4321
.define TMW $212E

; Sub screen layer window enable.
; Type: W8
; Bits: ...O 4321
.define TSW $212F

; main/sub screen color windows black/transparent regions (MS), fixed/subscreen (A), direct color (D).
; Type: W8
; Bits: MMSS ..AD
.define CGWSEL $2130

; Color math add/subtract (M), half (H), backdrop (B), layer enable (O4321).
; Type: W8
; Bits: MHBO 4321
.define CGADSUB $2131

; Fixed color channel select (BGR) and value (C).
; Type: W8
; Bits: BGRC CCCC
.define COLDATA $2132

; External sync (E), EXTBG (X), Hi-res (H), Overscan (O), OBJ interlace (i), Screen interlace (I).
; Type: W8
; Bits: EX.. HOiI
.define SETINI $2133

; 24-bit signed multiplication result.
; Type: R24
; Bits: LLLL LLLL
.define MPYL $2134
; Bits: MMMM MMMM
.define MPYM $2135
; Bits: HHHH HHHH
.define MPYH $2136

; Software latch for H/V counters.
; Type: R8
; Bits: .... ....
.define SLHV $2137

; Read OAM data byte, increments OAMADD byte.
; Type: R8
; Bits: DDDD DDDD
.define OAMDATAREAD $2138

; VRAM data read. Increments VMADD after read according to VMAIN setting.
; Type: R16
; Bits: LLLL LLLL
.define VMDATALREAD $2139
; Bits: HHHH HHHH
.define VMDATAHREAD $213A

; CGRAM data read. Increments CGADD byte address after each write.
; Type: R8x2
; Bits: .BBB BBGG GGGR RRRR
.define CGDATAREAD $213B

; Output horizontal counter.
; Type: R8x2
; Bits: ...H HHHH HHHH HHHH
.define OPHCT $213C

; Output vertical counter.
; Type: R8x2
; Bits: ...V VVVV VVVV VVVV
.define OPVCT $213D

; Sprite overflow (T), sprite tile overflow (R), master/slave (M), PPU1 version (V).
; Type: R8
; Bits: TRM. VVVV
.define STAT77 $213E

; Interlace field (F), counter latch value (L), NTSC/PAL (M), PPU2 version (V).
; Type: R8
; Bits: FL.M VVVV
.define STAT78 $213F

; Data to/from APU.
; Type: RW8
; Bits: DDDD DDDD
.define APUIO0 $2140
.define APUIO1 $2141
.define APUIO2 $2142
.define APUIO3 $2143

; Data to/from S-WRAM, increments WMADD.
; Type: RW8
; Bits: DDDD DDDD;
.define WMDATA $2180

; S-WRAM address for WMDATA access.
; Type W24
; Bits: LLLL LLLL
.define WMADDL $2181
; Bits: MMMM MMMM
.define WMADDM $2182
; Bits: .... ...H
.define WMADDH $2183

; Output to joypads (latches standard controllers).
; Type: W8;
; Bits: .... ...D
.define JOYOUT $4016

; Input from joypad 1.
; Type: R8;
; Bits: .... ..DD
.define JOYSER0 $4016

; Always 1 (1), input from joypad 2 (D).
; Type: R8
; Bits: ...1 11DD
.define JOYSER1 $4017

; Vblank NMI enable (N), timer IRQ mode (VH), joypad auto-read enable (J).
; Type: W8
; Bits: N.VH ...J
.define NMITIMEN $4200

; Joypad port 2 I/O (2), joypad port 1 I/O (1), unused I/O (D).
; Type: W8
; Bits: 21DD DDDD
.define WRIO $4201

; Unsigned multiplication factor A.
; Type: W8
; Bits: DDDD DDDD
.define WRMPYA $4202

; Unsigned multiplication factor B. starts 8-cycle multiplication.
; Type: W8
; Bits: DDDD DDDD
.define WRMPYB $4203

; Unsigned dividend.
; Type: W16
; Bits: LLLL LLLL
.define WRDIVL $4204
; Bits: HHHH HHHH
.define WRDIVH $4205

; Unsigned divisor, starts 16-cycle division.
; Type: W8
; Bits: DDDD DDDD
.define WRDIVB $4206

; H counter target for timer IRQ.
; Type: W16
; Bits: LLLL LLLL
.define HTIMEL $4207
; Bits: .... ...H
.define HTIMEH $4208

; V counter target for timer IRQ.
; Type: W16
; Bits: LLLL LLLL
.define VTIMEL $4209
; Bits: .... ...H
.define VTIMEH $420A

; DMA enable.
; Type: W8
; Bits: 7654 3210
.define MDMAEN $420B

; HDMA enable.
; Type: W8
; Bits: 7654 3210
.define HDMAEN $420C

; FastROM enable (F).
; Type: W8
; Bits: .... ...F
.define MEMSEL $420D

; Vblank NMI flag (N), CPU version (V).
; Type: R8
; Bits: N... VVVV
.define RDNMI $4210

; Timer IRQ flag (T).
; Type: R8
; Bits: T... ....
.define TIMEUP $4211

; Vblank flag (V), hblank flag (H), joypad auto-read in-progress flag (J).
; Type: R8
; Bits: VH.. ...J
.define HVBJOY $4212

; Joypad port 2 I/O (2), joypad port 1 I/O (1), unused I/O (D).
; Type: R8
; Bits: 21DD DDDD
.define RDIO $4213

; Unsigned quotient.
; Type: R16
; Bits: LLLL LLLL
.define RDDIVL $4214
; Bits: HHHH HHHH
.define RDDIVH $4215

; Unsigned product or unsigned remainder.
; Type: R16
; Bits: LLLL LLLL
.define RDMPYL $4216
; Bits: HHHH HHHH
.define RDMPYH $4217

; 16-bit joypad auto-read result (first read high to last read low).
; Type: R16
; Bits: LLLL LLLL
.define JOY1L $4218
; Bits: HHHH HHHH
.define JOY1H $4219
; Bits: LLLL LLLL
.define JOY2L $421A
; Bits: HHHH HHHH
.define JOY2H $421B
; Bits: LLLL LLLL
.define JOY3L $421C
; Bits: HHHH HHHH
.define JOY3H $421D
; Bits: LLLL LLLL
.define JOY4L $421E
; Bits: HHHH HHHH
.define JOY4H $421F

; Direction (D), indirect HDMA (I), address increment mode (A), transfer pattern (P).
; Type: RW8
; Bits: DI.A APPP
.define DMAP0 $4300
.define DMAP1 $4310
.define DMAP2 $4320
.define DMAP3 $4330
.define DMAP4 $4340
.define DMAP5 $4350
.define DMAP6 $4360
.define DMAP7 $4370

; B-bus address.
; Type: RW8
; Bits: AAAA AAAA
.define BBAD0 $4301
.define BBAD1 $4311
.define BBAD2 $4321
.define BBAD3 $4331
.define BBAD4 $4341
.define BBAD5 $4351
.define BBAD6 $4361
.define BBAD7 $4371

; DMA source address / HDMA table start address.
; Type: RW24
; Bits: LLLL LLLL
.define A1T0L $4302
.define A1T1L $4312
.define A1T2L $4322
.define A1T3L $4332
.define A1T4L $4342
.define A1T5L $4352
.define A1T6L $4362
.define A1T7L $4372
; Bits: HHHH HHHH
.define A1T0H $4303
.define A1T1H $4313
.define A1T2H $4323
.define A1T3H $4333
.define A1T4H $4343
.define A1T5H $4353
.define A1T6H $4363
.define A1T7H $4373
; Bits: BBBB BBBB
.define A1B0 $4304
.define A1B1 $4314
.define A1B2 $4324
.define A1B3 $4334
.define A1B4 $4344
.define A1B5 $4354
.define A1B6 $4364
.define A1B7 $4374

; DMA byte count (H:L) / HDMA indirect table address (B:H:L).
; Type: RW24
; Bits: LLLL LLLL
.define DAS0L $4305
.define DAS1L $4315
.define DAS2L $4325
.define DAS3L $4335
.define DAS4L $4345
.define DAS5L $4355
.define DAS6L $4365
.define DAS7L $4375
; Bits: HHHH HHHH
.define DAS0H $4306
.define DAS1H $4316
.define DAS2H $4326
.define DAS3H $4336
.define DAS4H $4346
.define DAS5H $4356
.define DAS6H $4366
.define DAS7H $4376
; Bits: BBBB BBBB
.define DAS0B $4307
.define DAS1B $4317
.define DAS2B $4327
.define DAS3B $4337
.define DAS4B $4347
.define DAS5B $4357
.define DAS6B $4367
.define DAS7B $4377

; HDMA table current address within bank (H:L).
; Type: R16
; Bits: LLLL LLLL
.define A2A0L $4308
.define A2A1L $4318
.define A2A2L $4328
.define A2A3L $4338
.define A2A4L $4348
.define A2A5L $4358
.define A2A6L $4368
.define A2A7L $4378
; Bits: HHHH HHHH
.define A2A0H $4309
.define A2A1H $4319
.define A2A2H $4329
.define A2A3H $4339
.define A2A4H $4349
.define A2A5H $4359
.define A2A6H $4369
.define A2A7H $4379

; HDMA reload flag (R) and scanline counter (L).
; Type: RW8
; Bits: RLLL LLLL
.define NLTR0 $430A
.define NLTR1 $431A
.define NLTR2 $432A
.define NLTR3 $433A
.define NLTR4 $434A
.define NLTR5 $435A
.define NLTR6 $436A
.define NLTR7 $437A
