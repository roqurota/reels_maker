import Foundation

/// Runs queued jobs one at a time through `claude -p` (DaVinci can only do one thing at once).
@MainActor
@Observable
final class JobRunner {
    @ObservationIgnored weak var store: Store?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var currentId: UUID?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var preparing = false
    var paused = false

    var isBusy: Bool { process != nil || preparing }

    func kick() {
        guard !paused, process == nil, !preparing, let store else { return }
        guard store.rootAvailable else { return }
        guard let i = store.jobs.firstIndex(where: { $0.status == .waiting }) else { return }
        let job = store.jobs[i]
        guard job.kind == .reel, DaVinci.needed(for: store.template(job.templateId)) else {
            start(index: i); return
        }
        // Open DaVinci first and wait for it, then start Claude.
        preparing = true
        let id = job.id
        store.jobs[i].status = .running
        store.jobs[i].note = "Проверяю DaVinci Resolve"
        Task { @MainActor in
            let problem = await DaVinci.ensureReady { [weak self] msg in
                guard let s = self?.store, let k = s.jobs.firstIndex(where: { $0.id == id }) else { return }
                s.jobs[k].note = msg
                s.jobs[k].log.append("… " + msg)
            }
            self.preparing = false
            guard let store = self.store, let k = store.jobs.firstIndex(where: { $0.id == id }) else { self.kick(); return }
            if store.jobs[k].status == .cancelled { self.kick(); return }
            if let problem {
                store.jobs[k].status = .failed
                store.jobs[k].note = problem
                store.jobs[k].log.append("✕ " + problem)
                self.paused = true
                store.lastError = problem
                store.saveJobs()
                return
            }
            store.jobs[k].log.append("✓ DaVinci Resolve готов")
            self.start(index: k)
        }
    }

    func stop(_ id: UUID) {
        guard currentId == id else { return }
        process?.terminate()
    }

    /// Called when the app quits so Claude doesn't keep working without anyone watching.
    func stopAll() {
        process?.terminate()
    }

    private func start(index i: Int) {
        guard let store else { return }
        var job = store.jobs[i]
        let fm = FileManager.default
        try? fm.createDirectory(atPath: job.workDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: job.outputDir, withIntermediateDirectories: true)

        var args = ["-p"]
        let isRevision = job.pendingRevision != nil && job.sessionStarted
        if isRevision {
            let comment = job.pendingRevision ?? ""
            args.append("Правка к этому же ролику: \(comment)\nПерезапиши тот же файл \(job.outputDir)/\(job.fileName ?? "") (для шаблона: тот же template.json) и обнови result.json. Вопросов не задавай.")
            args += ["--resume", job.sessionId.uuidString]
        } else {
            job.sessionId = UUID()
            args.append(job.prompt)
            args += ["--session-id", job.sessionId.uuidString]
            // task file for history and for a human to read
            let task: [String: Any] = [
                "title": job.title, "song": job.songName ?? "", "part": job.part ?? "",
                "template": job.templateName ?? "", "variant": job.variant, "moods": job.moods,
                "colors": job.colors, "wishes": job.wishes, "output": "\(job.outputDir)/\(job.fileName ?? "")",
                "session": job.sessionId.uuidString,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: task, options: [.prettyPrinted, .withoutEscapingSlashes]) {
                try? data.write(to: URL(fileURLWithPath: job.workDir).appendingPathComponent("task.json"))
            }
            try? job.prompt.write(toFile: job.workDir + "/prompt.md", atomically: true, encoding: .utf8)
        }
        args += ["--output-format", "stream-json", "--verbose",
                 "--permission-mode", store.permissionMode,
                 "-n", "Reels Studio: \(job.title)",
                 "--add-dir", store.reelsRoot, "--add-dir", store.songsRoot]
        if job.kind == .publish { args.append("--chrome") }   // drives the user's own Chrome through Claude in Chrome
        let mediaDirs = (job.mediaFolders ?? []).isEmpty ? [store.mediaRoot] : (job.mediaFolders ?? [])
        for f in mediaDirs where !f.isEmpty && !f.hasPrefix(store.reelsRoot) && !f.hasPrefix(store.songsRoot) { args += ["--add-dir", f] }
        if !store.model.isEmpty { args += ["--model", store.model] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: store.claudePath)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: job.workDir)
        var env = ProcessInfo.processInfo.environment
        let home = fm.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice

        let id = job.id
        buffer = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            Task { @MainActor in self?.consume(d, id: id) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor in self?.append(id, "stderr: " + s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.finished(id: id, code: code) }
        }

        job.status = .running
        job.startedAt = Date()
        job.note = isRevision ? "Вношу правку" : "Запуск Claude"
        job.log.append("▶ " + (isRevision ? "Правка в той же сессии" : "Старт") + " · " + Date().formatted(date: .omitted, time: .shortened))
        store.jobs[i] = job
        store.saveJobs()

        do {
            try p.run()
            process = p
            if let k = store.jobs.firstIndex(where: { $0.id == id }) { store.jobs[k].pid = p.processIdentifier }
            currentId = id
            if let k = store.jobs.firstIndex(where: { $0.id == id }) { store.jobs[k].sessionStarted = true }
        } catch {
            store.jobs[i].status = .failed
            store.jobs[i].note = "Не запустился Claude: \(error.localizedDescription). Проверь путь в настройках."
            store.saveJobs()
        }
    }

    private func consume(_ data: Data, id: UUID) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line, id: id)
        }
    }

    private func handle(_ line: Data, id: UUID) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "assistant":
            guard let msg = obj["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] else { return }
            for c in content {
                if c["type"] as? String == "text", let t = c["text"] as? String, !t.isEmpty {
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    append(id, trimmed)
                    setNote(id, String(trimmed.split(separator: "\n").first ?? ""))
                } else if c["type"] as? String == "tool_use" {
                    let name = c["name"] as? String ?? "tool"
                    let input = c["input"] as? [String: Any] ?? [:]
                    let desc = (input["description"] as? String) ?? (input["skill"] as? String).map { "скилл \($0)" }
                        ?? (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                    append(id, "→ \(name)\(desc.isEmpty ? "" : ": " + desc)")
                    if !desc.isEmpty { setNote(id, desc) }
                }
            }
        case "result":
            let isError = obj["is_error"] as? Bool ?? false
            if let r = obj["result"] as? String, !r.isEmpty { append(id, (isError ? "✕ " : "✓ ") + r) }
            if let cost = obj["total_cost_usd"] as? Double { append(id, String(format: "Стоимость сессии: $%.2f", cost)) }
        default: break
        }
    }

    private func append(_ id: UUID, _ text: String) {
        guard let store, let i = store.jobs.firstIndex(where: { $0.id == id }) else { return }
        store.jobs[i].log.append(text)
    }

    private func setNote(_ id: UUID, _ text: String) {
        guard let store, let i = store.jobs.firstIndex(where: { $0.id == id }) else { return }
        store.jobs[i].note = String(text.prefix(140))
    }

    private func finished(id: UUID, code: Int32) {
        process = nil
        currentId = nil
        guard let store, let i = store.jobs.firstIndex(where: { $0.id == id }) else { kick(); return }
        var job = store.jobs[i]
        job.finishedAt = Date()
        let wasRevision = job.pendingRevision != nil
        job.pendingRevision = nil
        if job.status == .cancelled {
            store.jobs[i] = job; store.saveJobs(); kick(); return
        }
        let fm = FileManager.default
        if job.kind == .reel {
            var files: [String] = []
            let resultURL = URL(fileURLWithPath: job.workDir).appendingPathComponent("result.json")
            if let d = try? Data(contentsOf: resultURL), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                files = (o["files"] as? [String] ?? []).filter { fm.fileExists(atPath: $0) }
                if let n = o["notes"] as? String { job.log.append("Итог: " + n) }
            }
            let expected = job.outputDir + "/" + (job.fileName ?? "")
            if files.isEmpty, fm.fileExists(atPath: expected) { files = [expected] }
            job.resultFiles = files
            if !files.isEmpty {
                job.status = .done
                job.note = wasRevision ? "Правка готова" : "Готово"
            } else {
                job.status = .failed
                job.note = code == 0 ? "Claude закончил, но ролика нет на месте" : "Ошибка (код \(code))"
            }
        } else if job.kind == .publish {
            var status = "", url: String?, notes = ""
            if let d = try? Data(contentsOf: URL(fileURLWithPath: job.workDir).appendingPathComponent("result.json")),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                status = (o["status"] as? String ?? "").uppercased(); url = o["url"] as? String; notes = o["notes"] as? String ?? ""
            }
            if !notes.isEmpty { job.log.append("Итог: " + notes) }
            switch status {
            case "PUBLISHED":
                job.status = .done; job.note = "Опубликовано" + (url.map { ": " + $0 } ?? "")
                if let id = job.entryId { store.markPublished(entryId: id, url: url) }
            case "PREPARED":
                job.status = .done; job.note = "Проверка пройдена: всё готово к публикации, кнопку не нажимал"
            case "NEED_LOGIN":
                job.status = .failed; job.note = "Нужно войти в TikTok в Chrome"
                paused = true
                store.lastError = "TikTok в Chrome не залогинен. Войди в TikTok в Chrome, потом в Очереди нажми «Повторить неудачные»."
            case "NO_SOUND":
                job.status = .failed; job.note = "На сайте не получилось поставить официальный трек, не публиковал"
            default:
                job.status = .failed; job.note = code == 0 ? "Публикация не подтвердилась" : "Ошибка (код \(code))"
            }
        } else if job.kind == .skillEdit {
            job.status = code == 0 ? .done : .failed
            job.note = code == 0 ? "Скилл обновлён" : "Скилл не обновился (код \(code))"
            if code == 0 { store.backupSkill(store.template(job.templateId)?.skill) }
            if let d = try? Data(contentsOf: URL(fileURLWithPath: job.workDir).appendingPathComponent("result.json")),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let n = o["notes"] as? String {
                job.log.append("Итог: " + n)
            }
        } else {
            let t = URL(fileURLWithPath: job.workDir).appendingPathComponent("template.json")
            var skill: String?
            if let d = try? Data(contentsOf: t), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { skill = o["skill"] as? String }
            job.status = fm.fileExists(atPath: t.path) ? .done : .failed
            if job.status == .done && !store.skillExists(skill) {
                job.status = .failed
                job.note = "Разбор есть, но скилл не создан"
            } else {
                job.note = job.status == .done ? "Разбор готов, скилл \(skill ?? "") создан" : "Разбор не получился (код \(code))"
            }
            if job.status == .done { store.backupSkill(skill) }
        }
        // Not signed in: every next job would fail the same way, so stop the queue and say how to fix it.
        let authFailed = job.status == .failed && job.log.suffix(6).contains { $0.localizedCaseInsensitiveContains("authenticate") || $0.localizedCaseInsensitiveContains("not logged in") || $0.contains("/login") }
        if authFailed {
            job.note = "Claude не вошёл в аккаунт"
            paused = true
            store.lastError = "Claude в Терминале не вошёл в аккаунт. Открой Терминал, выполни claude auth login и войди, потом нажми в Очереди «Повторить неудачные» и «Продолжить очередь»."
        }
        store.jobs[i] = job
        store.saveJobs()
        if job.status == .done { store.recordResults(of: job) }
        kick()
    }
}
