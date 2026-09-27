import CoreText
import SwiftUI

/// Carga la fuente de íconos embebida (Material Symbols Rounded, subconjunto de ~9 KB).
enum IconFont {
    private static let cgFont: CGFont? = {
        guard let data = Data(base64Encoded: IconFontData.base64, options: .ignoreUnknownCharacters),
              let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider) else { return nil }
        return font
    }()

    private static var cache: [CGFloat: Font] = [:]

    static func font(size: CGFloat) -> Font {
        if let cached = cache[size] { return cached }
        let font: Font
        if let cgFont {
            font = Font(CTFontCreateWithGraphicsFont(cgFont, size, nil, nil))
        } else {
            font = .system(size: size)
        }
        cache[size] = font
        return font
    }
}

/// Ícono del prototipo. Hereda el color de primer plano salvo que se indique `color`.
struct Icon: View {
    let symbol: MS
    var size: CGFloat = 16
    var color: Color? = nil

    init(_ symbol: MS, size: CGFloat = 16, color: Color? = nil) {
        self.symbol = symbol
        self.size = size
        self.color = color
    }

    var body: some View {
        let text = Text(verbatim: symbol.rawValue)
            .font(IconFont.font(size: size))
            .frame(width: size, height: size)
        if let color {
            text.foregroundStyle(color)
        } else {
            text
        }
    }
}
