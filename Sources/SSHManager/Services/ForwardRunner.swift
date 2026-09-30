import Foundation

/// 后台运行 `ssh -N -L/-R <spec> <alias>` 的端口转发进程管理。
/// 所有状态变更都落在主线程；进程异常退出（< 2 秒）会保留一条 failed 记录并展示 stderr。
final class ForwardRunner: ObservableObject {

    struct RunningForward: Identifiable {
        let id: UUID
        let hostAlias: String
        let spec: String
        let isRemote: Bool
        let pid: Int32
        let startedAt: Date
        var failed: Bool = false
        var message: String?
    }

    @Published private(set) var running: [RunningForward] = []
    private var processes: [UUID: Process] = [:]

    func isRunning(hostAlias: String, forward: PortForward, isRemote: Bool) -> Bool {
        running.contains {
            $0.hostAlias == hostAlias && $0.spec == forward.raw && $0.isRemote == isRemote && !$0.failed
        }
    }

    func start(hostAlias: String, forward: PortForward, isRemote: Bool) {
        guard forward.isValid else { return }
        if isRunning(hostAlias: hostAlias, forward: forward, isRemote: isRemote) { return }

        let id = forward.id
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-N", "-o", "ExitOnForwardFailure=yes", isRemote ? "-R" : "-L", forward.raw, hostAlias]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        let startedAt = Date()
        var errorText = ""
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                let chunk = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { errorText += chunk }
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.processes[id] = nil
                guard let index = self.running.firstIndex(where: { $0.id == id }) else { return }
                if Date().timeIntervalSince(startedAt) < 2 {
                    self.running[index].failed = true
                    let message = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.running[index].message = message.isEmpty ? "进程已退出" : message
                } else {
                    self.running.remove(at: index)
                }
            }
        }

        do {
            try process.run()
            processes[id] = process
            running.append(RunningForward(
                id: id,
                hostAlias: hostAlias,
                spec: forward.raw,
                isRemote: isRemote,
                pid: process.processIdentifier,
                startedAt: startedAt
            ))
        } catch {
            running.append(RunningForward(
                id: id,
                hostAlias: hostAlias,
                spec: forward.raw,
                isRemote: isRemote,
                pid: -1,
                startedAt: startedAt,
                failed: true,
                message: error.localizedDescription
            ))
        }
    }

    func stop(_ id: UUID) {
        if let process = processes[id] {
            if process.isRunning {
                process.terminate()
            }
        } else if let index = running.firstIndex(where: { $0.id == id }) {
            running.remove(at: index)
        }
    }

    func stopAll() {
        for process in processes.values where process.isRunning {
            process.terminate()
        }
        running.removeAll { $0.failed }
    }
}
