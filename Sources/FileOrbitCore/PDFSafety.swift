import Foundation
import CoreGraphics
import PDFKit

enum PDFSafety {
    static func modifiableDocument(_ input: URL) throws -> PDFDocument {
        let document = try NativeConverter.readablePDF(input)
        let widget = (0..<document.pageCount).contains { index in document.page(at: index)?.annotations.contains { $0.widgetFieldType == .signature } == true }
        guard !widget, !hasSignature(input) else {
            throw ConversionError.unsupported("This PDF is signed or contains signature fields. Modifying it could invalidate a signature, so the original is unchanged.")
        }
        return document
    }
    private static func hasSignature(_ input: URL) -> Bool {
        guard let pdf = CGPDFDocument(input as CFURL), let catalog = pdf.catalog else { return true }
        var permissions: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Perms", &permissions) { return true }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return false }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return false }
        return signedField(in: fields, depth: 0)
    }
    private static func signedField(in fields: CGPDFArrayRef, depth: Int) -> Bool {
        guard depth < 32 else { return true }
        for index in 0..<CGPDFArrayGetCount(fields) {
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field else { continue }
            var name: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(field, "FT", &name), let name, String(cString: name) == "Sig" { return true }
            var children: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(field, "Kids", &children), let children, signedField(in: children, depth: depth + 1) { return true }
        }
        return false
    }
}
