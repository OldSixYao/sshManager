import Foundation

/// 同步运行外部命令的小封装：stdin 接 /dev/null、带超时、收集 stdout/stderr。
struct ShellTask {

    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String

        var succeeded: Bool { status == 0 }

        var trimmedStdout: String {
            stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedStderr: String {
            stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 8) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdoutData = Data()
        var stderrData = Data()
        let readQueue = DispatchQueue(label: "com.sshmanager.shelltask.read")
        let readDone = DispatchSemaphore(value: 0)
        readQueue.async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        if readDone.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = readDone.wait(timeout: .now() + 2)
        }
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
