import CoreGraphics
import Foundation

enum ScreenshotFormat: String, CaseIterable {
    case png
    case pdf

    static let storageKey = "ScreenshotFormat"

    func persist(userDefaults: UserDefaults = .standard) {
        userDefaults.set(rawValue, forKey: Self.storageKey)
    }

    static func current(userDefaults: UserDefaults = .standard) -> ScreenshotFormat {
        ScreenshotFormat(rawValue: userDefaults.string(forKey: storageKey) ?? "") ?? .png
    }
}

enum PDFPaperSize: String, CaseIterable {
    case a4
    case letter

    static let storageKey = "PDFPaperSize"

    func persist(userDefaults: UserDefaults = .standard) {
        userDefaults.set(rawValue, forKey: Self.storageKey)
    }

    static func current(userDefaults: UserDefaults = .standard) -> PDFPaperSize {
        PDFPaperSize(rawValue: userDefaults.string(forKey: storageKey) ?? "") ?? .a4
    }

    var localizedTitle: String {
        switch self {
        case .a4:
            return LocalizationResolver.string("A4", fallback: "A4")
        case .letter:
            return LocalizationResolver.string("Letter", fallback: "Letter")
        }
    }

    var pageSize: CGSize {
        switch self {
        case .a4:
            return CGSize(width: 210 * 72 / 25.4, height: 297 * 72 / 25.4)
        case .letter:
            return CGSize(width: 612, height: 792)
        }
    }
}

enum ScreenshotPDF {
    /// Half-inch margins leave room for ordinary printer hardware margins.
    static let margin: CGFloat = 36

    static func data(for image: CGImage, paperSize: PDFPaperSize) -> Data? {
        var mediaBox = CGRect(origin: .zero, size: paperSize.pageSize)
        let printableRect = mediaBox.insetBy(dx: margin, dy: margin)
        let scale = printableRect.width / CGFloat(image.width)
        // Split at whole source rows so adjacent pages never skip or repeat a pixel.
        let rowsPerPage = max(1, Int((printableRect.height / scale).rounded(.down)))
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for firstRow in stride(from: 0, to: image.height, by: rowsPerPage) {
            let rowCount = min(rowsPerPage, image.height - firstRow)
            let sourceRect = CGRect(x: 0, y: firstRow, width: image.width, height: rowCount)
            guard let slice = image.cropping(to: sourceRect) else {
                context.closePDF()
                return nil
            }

            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.interpolationQuality = .high
            let height = CGFloat(rowCount) * scale
            context.draw(slice, in: CGRect(
                x: printableRect.minX,
                y: printableRect.maxY - height,
                width: printableRect.width,
                height: height
            ))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
