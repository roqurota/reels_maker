import AppKit
import Foundation

/// Starts DaVinci Resolve when a job needs it and waits until its scripting API answers.
enum DaVinci {
    static let bundleId = "com.blackmagic-design.DaVinciResolve"
    static let appURL = URL(fileURLWithPath: "/Applications/DaVinci Resolve/DaVinci Resolve.app")

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    /// Skills that render with their own Swift code don't need Resolve.
    static func needed(for template: ReelTemplate?) -> Bool {
        guard let t = template else { return false }
        return !["reels-sketch", "reels-winter"].contains(t.skill ?? "")
    }

    /// Returns nil when ready, otherwise a reason for the user.
    static func ensureReady(status: @escaping @MainActor (String) -> Void) async -> String? {
        let problem = await waitForResolve(status: status)
        if problem == nil { await leaveUntitled() }
        return problem
    }

    /// While Resolve sits on a never-saved "Untitled Project", switching projects pops a modal
    /// "Save current project" dialog that nobody answers in the background. Park Resolve on a
    /// named scratch project instead (right after launch the untitled one is still clean).
    static func leaveUntitled() async {
        _ = await python("""
        import DaVinciResolveScript as d
        pm = d.scriptapp("Resolve").GetProjectManager()
        cur = pm.GetCurrentProject()
        if cur is None or cur.GetName().startswith("Untitled"):
            if "Reels Studio" in (pm.GetProjectListInCurrentFolder() or []):
                pm.LoadProject("Reels Studio")
            else:
                pm.CreateProject("Reels Studio")
            pm.SaveProject()
        print("OK:" + pm.GetCurrentProject().GetName())
        """)
    }

    private static func waitForResolve(status: @escaping @MainActor (String) -> Void) async -> String? {
        if await ping() != nil { return nil }
        if !isRunning {
            await MainActor.run { status("Открываю DaVinci Resolve") }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            do { _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) }
            catch { return "Не открылся DaVinci Resolve: \(error.localizedDescription)" }
        }
        await MainActor.run { status("Жду, пока DaVinci Resolve загрузится") }
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(4))
            if await ping() != nil {
                try? await Task.sleep(for: .seconds(3))   // let the project manager settle
                return nil
            }
        }
        return isRunning
            ? "DaVinci открыт, но не отвечает скриптам. Проверь Preferences > General > External scripting using: Local"
            : "DaVinci Resolve не запустился за 5 минут"
    }

    /// Name of the current Resolve project, or nil if the scripting API doesn't answer.
    static func ping() async -> String? {
        await python("""
        import DaVinciResolveScript as d
        r = d.scriptapp("Resolve")
        pm = r.GetProjectManager() if r else None
        cur = pm.GetCurrentProject() if pm else None
        print("OK:" + (cur.GetName() if cur else "-") if pm else "NO")
        """)
    }

    /// Runs a snippet against Resolve's scripting API; returns what follows "OK:" or nil.
    static func python(_ code: String) async -> String? {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = ["-c", code]
            var env = ProcessInfo.processInfo.environment
            env["RESOLVE_SCRIPT_API"] = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
            env["RESOLVE_SCRIPT_LIB"] = appURL.path + "/Contents/Libraries/Fusion/fusionscript.so"
            env["PYTHONPATH"] = env["RESOLVE_SCRIPT_API"]! + "/Modules"
            p.environment = env
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            let resumed = LockedFlag()
            p.terminationHandler = { _ in
                let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if resumed.set() { cont.resume(returning: s.hasPrefix("OK:") ? String(s.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines) : nil) }
            }
            do { try p.run() } catch { if resumed.set() { cont.resume(returning: nil) }; return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                if p.isRunning { p.terminate() }
            }
        }
    }
}

final class LockedFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    /// true the first time only
    func set() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// Process helpers for jobs that outlived the app (app quit or crashed while Claude was working).
enum Proc {
    static func isClaude(_ pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
        let path = String(cString: buf)
        return path.hasSuffix("/claude") || path.contains("/claude/versions/")
    }
    static func terminate(_ pid: Int32) {
        if isClaude(pid) { kill(pid, SIGTERM) }
    }
}
