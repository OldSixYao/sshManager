import Darwin
import Foundation

/// 基于 glob(3) 的路径模式展开，支持 `~`（GLOB_TILDE）。
enum Glob {
    static func expand(_ pattern: String) -> [String] {
        var gt = glob_t()
        let result = pattern.withCString { patternString -> CInt in
            glob(patternString, GLOB_TILDE, nil, &gt)
        }
        defer { globfree(&gt) }
        guard result == 0 else { return [] }

        var paths: [String] = []
        for index in 0..<Int(gt.gl_pathc) {
            if let path = gt.gl_pathv[index] {
                paths.append(String(cString: path))
            }
        }
        return paths
    }
}
