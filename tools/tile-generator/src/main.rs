fn main() {
    // 第一引数を取得
    let args: Vec<String> = std::env::args().collect();

    let file_path = &args[1];

    // ファイルを開く
    let file = std::fs::File::open(file_path).expect("ファイルを開けませんでした");
    // ファイルを読み込む
    let mut reader = std::io::BufReader::new(file);

    // 画像ファイルとして読み込む
    let img = image::load(reader, image::ImageFormat::Png).expect("画像を読み込めませんでした");
}
