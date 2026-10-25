import Foundation

/// Mean local-window luminance SSIM. Inputs are aligned, normalized sRGB luma samples.
public enum StructuralSimilarity {
    public static func measure(_ lhs: [Double], _ rhs: [Double], width: Int, height: Int) throws -> Double {
        guard width > 0, height > 0, width <= 1_048_576 / height, lhs.count == width * height, rhs.count == lhs.count,
              lhs.allSatisfy({ $0.isFinite && (0...1).contains($0) }), rhs.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ConversionError.invalidInput("SSIM requires aligned finite luminance samples.")
        }
        if lhs == rhs { return 1 }
        let c1 = 0.01 * 0.01, c2 = 0.03 * 0.03
        var total = 0.0, windows = 0
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                var a = 0.0, b = 0.0, aa = 0.0, bb = 0.0, ab = 0.0, count = 0.0
                for yy in y..<min(y + 8, height) { for xx in x..<min(x + 8, width) {
                    let index = yy * width + xx, va = lhs[index], vb = rhs[index]
                    a += va; b += vb; aa += va * va; bb += vb * vb; ab += va * vb; count += 1
                } }
                let ma = a / count, mb = b / count
                let va = max(0, aa / count - ma * ma), vb = max(0, bb / count - mb * mb), covariance = ab / count - ma * mb
                total += ((2 * ma * mb + c1) * (2 * covariance + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2))
                windows += 1
            }
        }
        return min(1, max(-1, total / Double(windows)))
    }
}
