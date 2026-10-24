import Foundation
import Darwin

/// Runs an executable directly, in its own process group. File-backed diagnostics avoid pipe deadlocks.
public enum LocalProcess {
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval = 120,
                           cancellation: CancellationToken, directory: URL? = nil) throws -> String {
        try cancellation.check()
        guard timeout.isFinite, timeout > 0, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ConversionError.missingDependency("Converter is unavailable: \(executable.lastPathComponent). Check Settings.")
        }
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("fileorbit-process-\(UUID().uuidString).log")
        let fd = open(logURL.path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ConversionError.failed("Could not create the converter's temporary log.") }
        defer { close(fd); try? FileManager.default.removeItem(at: logURL) }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0, posix_spawnattr_init(&attributes) == 0 else {
            throw ConversionError.failed("Could not prepare the local converter.")
        }
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, fd, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fd, STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        if let directory {
            guard posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0 else {
                throw ConversionError.failed("Could not set the converter's working folder.")
            }
        }
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        let allocated = ([executable.path] + arguments).map { strdup($0) }
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        defer { allocated.forEach { free($0) }; environment.forEach { free($0) } }
        var argv = allocated + [nil]
        var envp = environment + [nil]
        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &envp)
        guard spawnResult == 0 else { throw ConversionError.failed("Could not launch \(executable.lastPathComponent): \(String(cString: strerror(spawnResult)))") }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var status: Int32 = 0
        var reaped = false
        defer {
            // The helper may have spawned a child. Never leave that child running after cancellation or completion.
            kill(-pid, SIGTERM)
            if !reaped {
                let stopDeadline = ProcessInfo.processInfo.systemUptime + 0.25
                while ProcessInfo.processInfo.systemUptime < stopDeadline {
                    if waitpid(pid, &status, WNOHANG) == pid { reaped = true; break }
                    usleep(10_000)
                }
                kill(-pid, SIGKILL)
                if !reaped { while waitpid(pid, &status, 0) == -1 && errno == EINTR {} }
            }
            kill(-pid, SIGKILL)
        }
        while true {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { reaped = true; break }
            if result == -1 && errno != EINTR { throw ConversionError.failed("Could not read the converter's exit status.") }
            try cancellation.check()
            if ProcessInfo.processInfo.systemUptime >= deadline { throw ConversionError.failed("\(executable.lastPathComponent) exceeded its \(Int(timeout.rounded(.up)))-second time limit. The job was stopped.") }
            var info = stat()
            if fstat(fd, &info) == 0, info.st_size > 8 * 1024 * 1024 { throw ConversionError.failed("The converter produced excessive diagnostics and was stopped.") }
            usleep(20_000)
        }
        try cancellation.check()
        var finalInfo = stat()
        if fstat(fd, &finalInfo) == 0, finalInfo.st_size > 8 * 1024 * 1024 { throw ConversionError.failed("The converter produced excessive diagnostics.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try handle.seek(toOffset: 0)
        let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
        let output = String(decoding: data, as: UTF8.self)
        let signal = status & 0x7f
        let exitCode = (status >> 8) & 0xff
        guard signal == 0, exitCode == 0 else {
            let details = String(output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(2000))
            throw ConversionError.failed("\(executable.lastPathComponent) failed \(signal == 0 ? "(exit \(exitCode))" : "(signal \(signal))").\(details.isEmpty ? "" : "\n" + details)")
        }
        return output
    }
}
