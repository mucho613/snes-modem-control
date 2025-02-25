use image::Pixel;

use std::env;
use std::fs::File;
use std::io::Write;

fn main() {
    let mut arg = env::args();
    arg.next();

    let image_path = match arg.next() {
        None => {
            println!("error");
            return;
        }
        Some(s) => s,
    };

    println!("Image Path is {}", image_path);
    test(image_path);
}

fn test(path: String) {
    let img = image::open(path).unwrap();
    let img = img.to_luma8();
    let size_x = img.width();
    let size_y = img.height();

    println!("Width: {}", size_x);
    println!("Height: {}", size_y);

    let mut pattern = File::create("pattern.bin").expect("Failed to create pattern file.");

    let mut buffer: Vec<u8> = Vec::new();

    for y_block in 0..33 {
        for x_block in 0..52 {
            for y_row in 0..8 {
                let x = x_block * 8;
                let y = y_block * 8 + y_row;

                let pixel0 = img.get_pixel(x + 0, y).to_luma()[0] > 0;
                let pixel1 = img.get_pixel(x + 1, y).to_luma()[0] > 0;
                let pixel2 = img.get_pixel(x + 2, y).to_luma()[0] > 0;
                let pixel3 = img.get_pixel(x + 3, y).to_luma()[0] > 0;
                let pixel4 = img.get_pixel(x + 4, y).to_luma()[0] > 0;
                let pixel5 = img.get_pixel(x + 5, y).to_luma()[0] > 0;
                let pixel6 = img.get_pixel(x + 6, y).to_luma()[0] > 0;
                let pixel7 = img.get_pixel(x + 7, y).to_luma()[0] > 0;

                let byte = if pixel0 == true { 1 << 7 } else { 0 }
                    | if pixel1 == true { 1 << 6 } else { 0 }
                    | if pixel2 == true { 1 << 5 } else { 0 }
                    | if pixel3 == true { 1 << 4 } else { 0 }
                    | if pixel4 == true { 1 << 3 } else { 0 }
                    | if pixel5 == true { 1 << 2 } else { 0 }
                    | if pixel6 == true { 1 << 1 } else { 0 }
                    | if pixel7 == true { 1 } else { 0 };

                buffer.push(u8::from(byte));
                buffer.push(0x00);
            }
        }
    }

    pattern.write_all(&buffer).expect("Cannot write");
}
