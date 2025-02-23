use std::fs::File;
use std::io::Write;

fn main() -> Result<(), std::io::Error> {
    let mut file = File::create("tilemap.bin")?;

    let mut data: Vec<u8> = Vec::new();
    let mut address: u16 = 0;
    for i in 0..1024 {
        // 以下の場合は 00 00 を追加
        // - i を 32 で割ったときに余りが 0～2 のとき
        // - i を 32 で割ったときに余りが 29～31 のとき
        if i % 32 <= 2 || i % 32 >= 29 {
            data.push(0);
            data.push(0);
            continue;
        }
        data.push((address & 0xFF) as u8);
        data.push(((address >> 8) & 0b0000_0011) as u8);
        address += 2;
    }
    // ファイルに書き込む
    file.write_all(&data)?;
    // ファイルを閉じる
    file.flush()?;
    file.sync_all()?;
    Ok(())
}
