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
    @Test func cancellationStopsRunningProcess() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-running-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let token = CancellationToken()
        let observation = CancellationObservation()
        let workerFinished = DispatchSemaphore(value: 0)
        // A shared dispatch timer can be delayed by parallel converter tests.
        // Signal from an independent thread after the subprocess actually starts,
        // and measure response time from the cancellation request itself.
        Thread.detachNewThread {
            defer { workerFinished.signal() }
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            var child: Int32?
            repeat {
                if let value = try? String(contentsOf: marker, encoding: .utf8),
                   let pid = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 {
                    child = pid
                    break
                }
                usleep(10_000)
            } while ProcessInfo.processInfo.systemUptime < deadline
            observation.record(child: child, requestedAt: ProcessInfo.processInfo.systemUptime)
            token.cancel()
        }
        do {
            _ = try LocalProcess.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                     arguments: ["-c", "echo $$ > \"$1\"; exec sleep 20", "fileorbit-test", marker.path],
                                     timeout: 15, cancellation: token)
            Issue.record("Expected cancellation")
        } catch ConversionError.cancelled {} catch { Issue.record("Unexpected error: \(error)") }
        let returnedAt = ProcessInfo.processInfo.systemUptime
        #expect(workerFinished.wait(timeout: .now() + 3) == .success)
        let recorded = observation.snapshot()
        let requestedAt = try #require(recorded.requestedAt)
        let child = try #require(recorded.child, "The subprocess must start before it is cancelled")
        #expect(returnedAt - requestedAt < 3)
        #expect(kill(child, 0) == -1)
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

private final class CancellationObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var child: Int32?
    private var requestedAt: TimeInterval?
    func record(child: Int32?, requestedAt: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        self.child = child; self.requestedAt = requestedAt
    }
    func snapshot() -> (child: Int32?, requestedAt: TimeInterval?) {
        lock.lock(); defer { lock.unlock() }
        return (child, requestedAt)
    }
}
