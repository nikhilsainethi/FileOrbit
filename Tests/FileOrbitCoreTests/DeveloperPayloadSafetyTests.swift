import Testing
import Foundation
@testable import FileOrbitCore
@Suite struct DeveloperPayloadSafetyTests {
 @Test func rejectsExternalXMLBase() throws {
  let text = ##"<svg xmlns="http://www.w3.org/2000/svg" xml:base="https://example.com/private.svg"><image href="#asset"/></svg>"##
  #expect(throws: (any Error).self) { try SVGPathMinifier.minify(Data(text.utf8)) }
 }
 @Test func rejectsStringURLImageSet() throws {
  let text = #"<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" style="background-image:image-set(&quot;https://example.com/image.png&quot; 1x)"/></svg>"#
  #expect(throws: (any Error).self) { try SVGPathMinifier.minify(Data(text.utf8)) }
 }
 @Test(arguments: ["M5,,5L110 8L12 95Z", "M,5 5L110 8", "M5 5,L110 8", "M5 5,", ",M5 5", "M5\u{00A0}5L10 10"])
 func rejectsMalformedCommaPathInsteadOfRepairingGeometry(_ path: String) throws {
  #expect(throws: (any Error).self) { try SVGPathMinifier.minifyPath(path) }
 }
 @Test func rejectsNumbersWhichSwiftDecimalWouldRound() throws {
  let data = Data(#"{"exact":12345678901234567890123456789012345678901234567890}"#.utf8)
  let value = try StructuredDocument.read(data, format: .json)
  #expect(throws: (any Error).self) { try StructuredDocument.write(value, format: .swift) }
 }
 @Test func boundsSwiftTemplateExpansionBeforeMaterializingHugeDAG() throws {
  var source = "import Foundation\n"
  for index in 0..<16 {
   source += "struct Type\(index): Codable {\nvar left: Type\(index + 1)\nvar right: Type\(index + 1)\n}\n"
  }
  source += "struct Type16: Codable {\nvar value: String\n}\n"
  do {
   _ = try SwiftSchema.template(from: source)
   Issue.record("An exponentially expanded schema must stop at the running node budget.")
  } catch {
   #expect(error.localizedDescription.contains("100,000"))
  }
 }
 @Test func exactlyRepresentableDecimalsRemainSupported() throws {
  let data = Data(#"{"small":0.125,"large":12345678901234567890123456789012345678,"trailing":1250000000000000000000000000000000000000000}"#.utf8)
  let value = try StructuredDocument.read(data, format: .json)
  let generated = try StructuredDocument.write(value, format: .swift)
  #expect(String(decoding: generated, as: UTF8.self).contains("Decimal"))
 }
 @Test func rejectsOverwideSwiftModelAndSchemaInput() throws {
  let value = StructuredValue.object(Dictionary(uniqueKeysWithValues: (0..<513).map { ("key\($0)", StructuredValue.string("fixture")) }))
  #expect(throws: (any Error).self) { try StructuredDocument.write(value, format: .swift) }
  let fields = (0..<513).map { "var key\($0): String" }.joined(separator: "\n")
  let source = "struct RootPayload: Codable {\n" + fields + "\n}\n"
  do { _ = try SwiftSchema.template(from: source); Issue.record("Overwide Swift schema was accepted.") } catch { }
 }
 @Test func boundsSparseRecordInferenceBeforeKeyRecordCrossProduct() throws {
  let records = (0..<2001).map { index in StructuredValue.object(["field\(index % 500)": .string("sample")]) }
  do { _ = try StructuredDocument.write(.array(records), format: .swift); Issue.record("Sparse record schema exceeded the inference work budget.") } catch { }
 }
}
