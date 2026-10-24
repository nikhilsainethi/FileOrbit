import Testing
import Foundation
import Darwin
@testable import FileOrbitCore

@Suite struct ProcessTests {
    @Test func argumentsAreLiteralAndOutputIsCaptured() throws {
        let result = try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "a b; $(echo wrong) — résumé"], cancellation: CancellationToken())
        #expect(result == "a b; $(echo wrong) — résumé")
    }
    @Test func largeOutputCannotDeadlockPipe() throws {
        let result = try LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "i=0; while [ $i -lt 12000 ]; do echo 12345678901234567890; i=$((i+1)); done"], timeout: 8, cancellation: CancellationToken())
        #expect(result.count > 200_000)
    }
    @Test func timeoutStopsProcessPromptly() {
        let start = Date()
        #expect(throws: (any Error).self) { try LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], timeout: 0.15, cancellation: CancellationToken()) }
        #expect(Date().timeIntervalSince(start) < 3)
    }
    @Test func cancellationStopsRunningProcess() {
        let token = CancellationToken()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { token.cancel() }
        let start = Date()
        do {
            _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], cancellation: token)
            Issue.record("Expected cancellation")
        } catch ConversionError.cancelled {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(Date().timeIntervalSince(start) < 3)
    }
    @Test func nonzeroExitIncludesDiagnostic() {
        do {
            _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo converter-broke >&2; exit 7"], cancellation: CancellationToken())
            Issue.record("Expected failed exit")
        } catch { #expect(error.localizedDescription.contains("converter-broke")) }
    }
    @Test func preCancelledJobNeverLaunches() {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-cancel-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: target) }
        let token = CancellationToken(); token.cancel()
        #expect(throws: (any Error).self) { try LocalProcess.run(executable: URL(fileURLWithPath: "/usr/bin/touch"), arguments: [target.path], cancellation: token) }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
    @Test func timeoutTerminatesChildProcessGroup() throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-child-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: target) }
        #expect(throws: (any Error).self) { try LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 30 & echo $! > \"$1\"; wait", "fileorbit-test", target.path], timeout: 0.25, cancellation: CancellationToken()) }
        let pid = try #require(Int32(try String(contentsOf: target, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let end = ProcessInfo.processInfo.systemUptime + 2
        while kill(pid, 0) == 0 && ProcessInfo.processInfo.systemUptime < end { usleep(20_000) }
        #expect(kill(pid, 0) == -1)
    }
}
