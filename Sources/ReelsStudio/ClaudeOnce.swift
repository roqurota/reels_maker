import Foundation

/// Quick one-shot `claude -p` call outside the job queue (for small text tasks like captions),
/// so it doesn't wait behind a 20-minute DaVinci job.
@MainActor
enum ClaudeOnce {
    static func run(_ prompt: String, store: Store) async -> Result<String, Error> {
        let claude = store.claudePath
        let root = store.reelsRoot
        return await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.arguments = ["-p", prompt, "--output-format", "json", "--permission-mode", "auto", "--add-dir", root]
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { _ in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    cont.resume(returning: .failure(Msg("Claude не ответил"))); return
                }
                if o["is_error"] as? Bool == true {
                    cont.resume(returning: .failure(Msg((o["result"] as? String) ?? "ошибка Claude"))); return
                }
                cont.resume(returning: .success(o["result"] as? String ?? ""))
            }
            do { try p.run() } catch { cont.resume(returning: .failure(error)) }
        }
    }

    /// Pulls the first JSON array of strings out of Claude's answer.
    static func strings(from text: String) -> [String] {
        guard let a = text.firstIndex(of: "["), let b = text.lastIndex(of: "]"), a < b,
              let data = String(text[a...b]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

struct Msg: LocalizedError {
    let text: String
    init(_ t: String) { text = t }
    var errorDescription: String? { text }
}
