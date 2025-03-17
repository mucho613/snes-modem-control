use std::fs::File;
use std::io::Write;

fn main() -> Result<(), std::io::Error> {
    let mut file = File::create("../../assets/tilemap.bin")?;

    let mut data: Vec<u8> = Vec::new();
    let mut address: u16;

    address = 0x0000;
    for i in 0..0x0260 {
        // 左右の空白は 0x0000 のタイルを指定
        if i % 32 <= 2 || i % 32 >= 29 {
            data.push(0);
            data.push(0);
            continue;
        }
        data.push((address & 0xFF) as u8);
        data.push(((address >> 8) & 0b0000_0011) as u8);
        address += 2;
    }

    address = 0x00dc;
    for i in 0..0x01c0 {
        // 左右の空白は 0x0000 のタイルを指定
        if i % 32 <= 2 || i % 32 >= 29 {
            data.push(0);
            data.push(0);
            continue;
        }
        data.push((address & 0xFF) as u8);
        data.push(((address >> 8) & 0b0000_0011) as u8);
        address += 2;
    }

    address = 0x0000;
    for i in 0..0x0260 {
        // 左右の空白は 0x0000 のタイルを指定
        if i % 32 <= 2 || i % 32 >= 29 {
            data.push(0);
            data.push(0);
            continue;
        }
        data.push((address & 0xFF) as u8);
        data.push(((address >> 8) & 0b0000_0011) as u8);
        address += 2;
    }

    address = 0x00dc;
    for i in 0..0x01c0 {
        // 左右の空白は 0x0000 のタイルを指定
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
