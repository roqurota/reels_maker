import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class Store {
    // Settings (persisted in UserDefaults)
    var reelsRoot: String { didSet { UserDefaults.standard.set(reelsRoot, forKey: "reelsRoot") } }
    var songsRoot: String { didSet { UserDefaults.standard.set(songsRoot, forKey: "songsRoot") } }
    var claudePath: String { didSet { UserDefaults.standard.set(claudePath, forKey: "claudePath") } }
    var permissionMode: String { didSet { UserDefaults.standard.set(permissionMode, forKey: "permissionMode") } }
    var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    /// Shared footage folder: used whole when a song/task has no folders of its own.
    var mediaRoot: String { didSet { UserDefaults.standard.set(mediaRoot, forKey: "mediaRoot") } }

    var songs: [Song] = []
    var templates: [ReelTemplate] = []
    var jobs: [Job] = []
    var journal: [ReelEntry] = []
    var lastError: String?

    // New template flow survives closing the sheet
    var draftAnalyzeJobId: UUID?

    let runner = JobRunner()
    static weak var current: Store?

    init() {
        let d = UserDefaults.standard
        reelsRoot = d.string(forKey: "reelsRoot") ?? "/Volumes/The Last Roman/Reels Claude"
        songsRoot = d.string(forKey: "songsRoot") ?? "/Volumes/The Last Roman/The Last Roman/Songs"
        claudePath = d.string(forKey: "claudePath") ?? Store.findClaude()
        permissionMode = d.string(forKey: "permissionMode") ?? "auto"
        model = d.string(forKey: "model") ?? ""
        mediaRoot = d.string(forKey: "mediaRoot") ?? "/Volumes/The Last Roman/The Last Roman/Media/Video"
        load()
        runner.store = self
        // jobs that were running when the app quit are re-queued
        Store.current = self
        for i in jobs.indices where jobs[i].status == .running {
            if let pid = jobs[i].pid { Proc.terminate(pid) }   // Claude left over from the last app run
            jobs[i].status = .waiting
            jobs[i].note = "Перезапуск после закрытия приложения"
        }
        runner.kick()
    }

    static func findClaude() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for p in ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "\(home)/.local/bin/claude"
    }

    // MARK: Paths

    var studioDir: URL { URL(fileURLWithPath: reelsRoot).appendingPathComponent("_studio") }
    var songsFile: URL { studioDir.appendingPathComponent("songs.json") }
    var templatesDir: URL { studioDir.appendingPathComponent("templates") }
    var jobsFile: URL { studioDir.appendingPathComponent("jobs.json") }
    var journalFile: URL { studioDir.appendingPathComponent("reels.json") }
    /// All Pexels downloads, one subfolder per song; lives next to the app data, not inside the app.
    var pexelsDir: URL { studioDir.appendingPathComponent("pexels") }
    var rootAvailable: Bool { FileManager.default.fileExists(atPath: reelsRoot) }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func dayFolder(_ date: Date = Date()) -> URL {
        URL(fileURLWithPath: reelsRoot).appendingPathComponent(Store.dayFormatter.string(from: date))
    }

    // MARK: Load / save

    func load() {
        lastError = nil
        guard rootAvailable else {
            lastError = "Папка \(reelsRoot) недоступна. Подключи диск или поменяй папку в настройках."
            songs = []; templates = ReelTemplate.builtIns; jobs = []; journal = []
            return
        }
        try? FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)

        if let s: [Song] = readJSON(songsFile) {
            songs = s
        } else {
            songs = scanSongsFolder()
            saveSongs()
        }
        songs = songs.map { refreshParts($0) }

        templates = ReelTemplate.builtIns
        if let files = try? FileManager.default.contentsOfDirectory(at: templatesDir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "json" {
                if let t: ReelTemplate = readJSON(f) {
                    if let i = templates.firstIndex(where: { $0.id == t.id }) { templates[i] = t } else { templates.append(t) }
                }
            }
        }
        for i in templates.indices where templates[i].previewPath == nil {
            if let p = ReelTemplate.knownExamples[templates[i].id], FileManager.default.fileExists(atPath: p) { templates[i].previewPath = p }
        }
        for t in templates { backupSkill(t.skill, onlyIfMissing: true) }
        jobs = readJSON(jobsFile) ?? []
        journal = readJSON(journalFile) ?? []
        loadDrafts()
        writeTools()
    }

    func saveSongs() { writeJSON(songs.map { var s = $0; s.parts = []; return s }, songsFile) }
    func saveJobs() { writeJSON(jobs.map { var j = $0; j.log = Array(j.log.suffix(400)); return j }, jobsFile) }
    func saveJournal() { writeJSON(journal, journalFile) }

    // MARK: Publishing
    var publishFile: URL { studioDir.appendingPathComponent("publish.json") }
    var drafts: [UUID: PublishDraft] = [:]
    var captionLanguage: String { get { UserDefaults.standard.string(forKey: "captionLanguage") ?? "English" } }

    var clipTool: URL { studioDir.appendingPathComponent("tools/clip.swift") }

    /// Small helper Claude uses to put a big video on the macOS clipboard as a file,
    /// so it can be pasted into TikTok's upload page (Claude in Chrome uploads only up to 10 MB).
    func writeTools() {
        let src = """
        import AppKit
        let pb = NSPasteboard.general
        pb.clearContents()
        print(pb.writeObjects([URL(fileURLWithPath: CommandLine.arguments[1]) as NSURL]) ? "ok" : "failed")
        """
        try? FileManager.default.createDirectory(at: clipTool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? src.write(to: clipTool, atomically: true, encoding: .utf8)
    }

    func loadDrafts() {
        guard let d = try? Data(contentsOf: publishFile),
              let m = try? JSONDecoder().decode([String: PublishDraft].self, from: d) else { return }
        drafts = Dictionary(uniqueKeysWithValues: m.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }
    func saveDrafts() { writeJSON(Dictionary(uniqueKeysWithValues: drafts.map { ($0.key.uuidString, $0.value) }), publishFile) }

    func enqueuePublish(entryIds: [UUID], dryRun: Bool) -> Int {
        var n = 0
        for id in entryIds {
            guard let e = journal.first(where: { $0.id == id }), let d = drafts[id] else { continue }
            let work = studioDir.appendingPathComponent("publish").appendingPathComponent(Store.dayFormatter.string(from: Date()) + "_" + URL(fileURLWithPath: e.file).deletingPathExtension().lastPathComponent + "_" + UUID().uuidString.prefix(6))
            var job = Job(kind: .publish, title: (dryRun ? "Проверка TikTok: " : "TikTok: ") + URL(fileURLWithPath: e.file).lastPathComponent, workDir: work.path, outputDir: work.path)
            job.entryId = id; job.dryRun = dryRun; job.songName = e.song; job.part = e.part; job.templateName = e.template
            job.prompt = Prompts.publish(entry: e, draft: d, song: songs.first { $0.name == e.song }, dryRun: dryRun, workDir: work.path, store: self)
            jobs.append(job); n += 1
        }
        saveJobs(); runner.kick()
        return n
    }

    func markPublished(entryId: UUID, url: String?) {
        guard let i = journal.firstIndex(where: { $0.id == entryId }) else { return }
        journal[i].published = true
        if !journal[i].platforms.contains("TikTok") { journal[i].platforms = journal[i].platforms.isEmpty ? "TikTok" : journal[i].platforms + ", TikTok" }
        if let url, !url.isEmpty { journal[i].tiktokURL = url }
        saveJournal()
    }
    func saveTemplate(_ t: ReelTemplate) {
        writeJSON(t, templatesDir.appendingPathComponent("\(t.id).json"))
        if let i = templates.firstIndex(where: { $0.id == t.id }) { templates[i] = t } else { templates.append(t) }
    }
    var activeTemplates: [ReelTemplate] { templates.filter { !($0.archived ?? false) } }
    var archivedTemplates: [ReelTemplate] { templates.filter { $0.archived ?? false } }

    func setArchived(_ id: String, _ value: Bool) {
        guard var t = template(id) else { return }
        t.archived = value
        saveTemplate(t)
    }

    func deleteTemplate(_ t: ReelTemplate) {
        try? FileManager.default.removeItem(at: templatesDir.appendingPathComponent("\(t.id).json"))
        templates.removeAll { $0.id == t.id && !$0.builtIn }
    }

    private func readJSON<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        do { return try dec.decode(T.self, from: data) } catch {
            lastError = "Не читается \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, _ url: URL) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try enc.encode(value).write(to: url, options: .atomic)
        } catch { lastError = "Не сохранилось \(url.lastPathComponent): \(error.localizedDescription)" }
    }

    // MARK: Songs

    func upsert(_ song: Song) {
        let s = refreshParts(song)
        if let i = songs.firstIndex(where: { $0.id == s.id }) { songs[i] = s } else { songs.append(s) }
        saveSongs()
    }

    func delete(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        saveSongs()
    }

    /// First run: build the library from Songs/<song>/Titles folders.
    func scanSongsFolder() -> [Song] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: songsRoot)
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else { return [] }
        var out: [Song] = []
        func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
        func hasTitles(_ u: URL) -> Bool { fm.fileExists(atPath: u.appendingPathComponent("Titles").path) }
        func make(_ u: URL, release: String) -> Song {
            var s = Song.newEmpty()
            s.id = (release == "Сингл" ? "" : release + "/") + u.lastPathComponent
            s.name = u.lastPathComponent; s.release = release; s.folder = u.path
            return s
        }
        for d in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where isDir(d) {
            if hasTitles(d) { out.append(make(d, release: "Сингл")); continue }
            let subs = ((try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []).filter(isDir)
            let songSubs = subs.filter(hasTitles)
            if !songSubs.isEmpty {
                for s in songSubs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) { out.append(make(s, release: d.lastPathComponent)) }
            } else {
                out.append(make(d, release: "Сингл"))
            }
        }
        return out
    }

    /// Reads <folder>/Titles/<Part>_words.srt and <Part>.wav.
    func refreshParts(_ song: Song) -> Song {
        var s = song
        s.parts = Store.detectParts(folder: song.folder)
        return s
    }

    nonisolated static let partOrder = ["Intro", "Verse 1", "Pre-Chorus", "Chorus", "Chorus 1", "Verse 2", "Chorus 2", "Verse 3", "Chorus 3", "Bridge", "Bridge 1", "Bridge 2", "Outro"]

    nonisolated static func detectParts(folder: String) -> [SongPart] {
        guard !folder.isEmpty else { return [] }
        let titles = URL(fileURLWithPath: folder).appendingPathComponent("Titles")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: titles.path) else { return [] }
        var parts: [SongPart] = []
        for f in files where f.hasSuffix("_words.srt") && !f.hasPrefix(".") {
            let name = String(f.dropLast("_words.srt".count))
            let srtURL = titles.appendingPathComponent(f)
            let wav = titles.appendingPathComponent("\(name).wav")
            let (dur, line) = parseSRT(srtURL)
            parts.append(SongPart(name: name,
                                  wav: FileManager.default.fileExists(atPath: wav.path) ? wav.path : nil,
                                  srt: srtURL.path, duration: dur, firstLine: line))
        }
        return parts.sorted { a, b in
            let ia = partOrder.firstIndex(of: a.name) ?? 99, ib = partOrder.firstIndex(of: b.name) ?? 99
            return ia == ib ? a.name < b.name : ia < ib
        }
    }

    nonisolated static func parseSRT(_ url: URL) -> (Double?, String?) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return (nil, nil) }
        var words: [String] = []
        var lastEnd: Double?
        for block in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n").map(String.init)
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let endStr = lines[ti].components(separatedBy: "-->").last?.trimmingCharacters(in: .whitespaces) ?? ""
            lastEnd = srtTime(endStr) ?? lastEnd
            if words.count < 9 { words += lines[(ti + 1)...].joined(separator: " ").split(separator: " ").map(String.init) }
        }
        let line = words.prefix(9).joined(separator: " ")
        return (lastEnd, line.isEmpty ? nil : line)
    }

    nonisolated static func srtTime(_ s: String) -> Double? {
        let p = s.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard p.count == 3, let h = Double(p[0]), let m = Double(p[1]), let sec = Double(p[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }

    // MARK: Jobs

    func template(_ id: String?) -> ReelTemplate? { templates.first { $0.id == id } }
    func song(_ id: String?) -> Song? { songs.first { $0.id == id } }

    static func fileSafe(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "/", with: "-")
    }

    func plannedFileName(song: Song, part: String, template: ReelTemplate, variant: Int) -> String {
        "\(Store.fileSafe(song.name))_\(Store.fileSafe(part))_\(template.short)_v\(variant).mp4"
    }

    /// Next free variant number so files from earlier runs today are never overwritten.
    func freeVariant(song: Song, part: String, template: ReelTemplate, from v: Int, taken: Set<String>) -> Int {
        var n = v
        let dir = dayFolder().appendingPathComponent(song.name)
        while true {
            let name = plannedFileName(song: song, part: part, template: template, variant: n)
            if !taken.contains(name) && !FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
                && !jobs.contains(where: { $0.fileName == name && $0.outputDir == dir.path && $0.status != .cancelled && $0.status != .failed }) {
                return n
            }
            n += 1
        }
    }

    func enqueueReels(song: Song, picks: [(part: String, templateId: String)], variants: Int,
                      moods: [String], colors: [String], wishes: String, previewFor: String? = nil,
                      mediaFolders: [String]? = nil, usePexels: Bool? = nil) -> Int {
        let out = dayFolder().appendingPathComponent(song.name)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var count = 0
        var taken = Set<String>()
        for pick in picks {
            guard let t = template(pick.templateId) else { continue }
            for v in 1...max(1, variants) {
                let variant = freeVariant(song: song, part: pick.part, template: t, from: v, taken: taken)
                let file = plannedFileName(song: song, part: pick.part, template: t, variant: variant)
                taken.insert(file)
                var job = Job(title: "\(song.name) · \(pick.part) · \(t.name)", workDir: "", outputDir: out.path)
                job.songId = song.id; job.songName = song.name; job.part = pick.part
                job.templateId = t.id; job.templateName = t.name; job.variant = variant
                job.moods = moods; job.colors = colors; job.wishes = wishes; job.fileName = file
                job.previewFor = previewFor
                job.mediaFolders = mediaFolders ?? song.media
                job.usePexels = usePexels ?? song.pexels
                let work = out.appendingPathComponent("_jobs").appendingPathComponent(file.replacingOccurrences(of: ".mp4", with: "") + "_" + job.id.uuidString.prefix(6))
                job.workDir = work.path
                job.prompt = Prompts.reel(job: job, song: song, template: t, store: self)
                jobs.append(job)
                count += 1
            }
        }
        saveJobs()
        runner.kick()
        return count
    }

    func enqueueAnalyze(reference: String, about: String, files: [String]) -> UUID {
        let work = studioDir.appendingPathComponent("analyze").appendingPathComponent(Store.dayFormatter.string(from: Date()) + "_" + UUID().uuidString.prefix(6))
        var job = Job(kind: .analyze, title: "Разбор референса", workDir: work.path, outputDir: work.path)
        job.prompt = Prompts.analyze(reference: reference, about: about, files: files, workDir: work.path, store: self)
        jobs.append(job)
        saveJobs()
        runner.kick()
        return job.id
    }

    /// A template change becomes a permanent rule in that template's skill.
    @discardableResult
    func enqueueSkillEdit(templateId: String, change: String) -> UUID? {
        guard let t = template(templateId), let skill = t.skill, !skill.isEmpty else { return nil }
        let work = studioDir.appendingPathComponent("skill-edits").appendingPathComponent(Store.dayFormatter.string(from: Date()) + "_" + skill + "_" + UUID().uuidString.prefix(6))
        var job = Job(kind: .skillEdit, title: "Шаблон «\(t.name)»: правка скилла", workDir: work.path, outputDir: work.path)
        job.templateId = t.id; job.templateName = t.name; job.wishes = change
        job.prompt = Prompts.skillEdit(template: t, skill: skill, change: change, workDir: work.path, store: self)
        jobs.append(job)
        saveJobs()
        runner.kick()
        return job.id
    }

    static var skillsHome: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills") }
    var skillsBackupDir: URL { studioDir.appendingPathComponent("skills") }

    func skillExists(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: Store.skillsHome.appendingPathComponent(name).appendingPathComponent("SKILL.md").path)
    }

    /// Copy of ~/.claude/skills/<name> next to the app data, so templates survive a new Mac or a wiped ~/.claude.
    func backupSkill(_ name: String?, onlyIfMissing: Bool = false) {
        guard let name, skillExists(name) else { return }
        let fm = FileManager.default
        let dst = skillsBackupDir.appendingPathComponent(name)
        if onlyIfMissing && fm.fileExists(atPath: dst.path) { return }
        try? fm.createDirectory(at: skillsBackupDir, withIntermediateDirectories: true)
        try? fm.removeItem(at: dst)
        try? fm.copyItem(at: Store.skillsHome.appendingPathComponent(name), to: dst)
    }

    func revise(_ jobId: UUID, comment: String) {
        guard let i = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[i].pendingRevision = comment
        jobs[i].status = .waiting
        jobs[i].note = "Правка: \(comment)"
        jobs[i].log.append("— Правка: \(comment)")
        jobs[i].revisions = (jobs[i].revisions ?? []) + [comment]
        saveJobs()
        runner.kick()
    }

    func retry(_ jobId: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        jobs[i].status = .waiting
        jobs[i].note = "Повтор"
        saveJobs(); runner.kick()
    }

    func retryFailed() {
        for i in jobs.indices where jobs[i].status == .failed {
            jobs[i].status = .waiting
            jobs[i].note = "Повтор"
        }
        lastError = nil
        runner.paused = false
        saveJobs(); runner.kick()
    }

    func cancel(_ jobId: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        if jobs[i].status == .running {
            runner.stop(jobId)
            if let pid = jobs[i].pid { Proc.terminate(pid) }
        }
        jobs[i].status = .cancelled
        jobs[i].note = "Отменено"
        saveJobs(); runner.kick()
    }

    func remove(_ jobId: UUID) {
        if let j = jobs.first(where: { $0.id == jobId }), j.status == .running { runner.stop(jobId) }
        jobs.removeAll { $0.id == jobId }
        saveJobs()
    }

    func clearFinished() {
        jobs.removeAll { $0.status == .done || $0.status == .cancelled }
        saveJobs()
    }

    func setPreview(templateId: String, file: String) {
        guard var t = template(templateId) else { return }
        t.previewPath = file
        saveTemplate(t)
    }

    /// Called by the runner when a reel job finished; records the files in the journal.
    func recordResults(of job: Job) {
        guard job.kind == .reel else { return }
        if let tid = job.previewFor, let f = job.resultFiles.first { setPreview(templateId: tid, file: f) }
        for f in job.resultFiles where !journal.contains(where: { $0.file == f }) {
            journal.insert(ReelEntry(date: job.finishedAt ?? Date(), file: f, song: job.songName ?? "",
                                     part: job.part ?? "", template: job.templateName ?? ""), at: 0)
        }
        saveJournal()
    }

    var madeToday: Int {
        journal.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    func madeCount(song: Song) -> Int { journal.filter { $0.song == song.name }.count }
}
