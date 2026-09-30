import Darwin
import Foundation

/// 监听 config 文件变化（含原子替换导致的 rename/delete），变化后回调并自动重挂监听。
final class ConfigWatcher {

    private let path: String
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private(set) var isWatching = false

    var onChange: (() -> Void)?

    init(path: String) {
        self.path = path
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }

    func start() {
        arm()
    }

    private func arm() {
        if let existing = source {
            existing.cancel()
            source = nil
        }
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            isWatching = false
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename, .link],
            queue: .main
        )
        newSource.setEventHandler { [weak self] in
            self?.handleEvent()
        }
        newSource.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }
        source = newSource
        newSource.resume()
        isWatching = true
    }

    private func handleEvent() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onChange?()
            self.arm()
        }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }
}
