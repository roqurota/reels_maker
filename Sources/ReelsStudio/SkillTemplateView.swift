import SwiftUI
import UniformTypeIdentifiers

struct SkillInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
    let path: String
}

@MainActor
enum Skills {
    /// name/description from the SKILL.md frontmatter
    static func frontmatter(_ md: String) -> (name: String?, description: String?) {
        guard md.hasPrefix("---") else { return (nil, nil) }
        let parts = md.components(separatedBy: "\n---")
        guard let head = parts.first else { return (nil, nil) }
        var name: String?, desc: String?
        for line in head.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("name:") { name = l.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            if l.hasPrefix("description:") { desc = l.dropFirst(12).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        }
        return (name, desc)
    }

    static func all() -> [SkillInfo] {
        let fm = FileManager.default
        let home = Store.skillsHome
        let dirs = (try? fm.contentsOfDirectory(atPath: home.path)) ?? []
        return dirs.sorted().compactMap { d in
            let md = home.appendingPathComponent(d).appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: md, encoding: .utf8) else { return nil }
            let f = frontmatter(text)
            return SkillInfo(name: d, description: f.description ?? "", path: md.path)
        }
    }

    /// Copies a skill folder (or a lone SKILL.md / *.md) into ~/.claude/skills. Returns the skill name.
    static func importSkill(from url: URL) throws -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        let mdURL = isDir.boolValue ? url.appendingPathComponent("SKILL.md") : url
        let text = try String(contentsOf: mdURL, encoding: .utf8)
        let raw = Skills.frontmatter(text).name ?? (isDir.boolValue ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
        let name = raw.lowercased().replacingOccurrences(of: " ", with: "-")
        let dst = Store.skillsHome.appendingPathComponent(name)
        if dst.standardizedFileURL == url.standardizedFileURL || dst.standardizedFileURL == url.deletingLastPathComponent().standardizedFileURL { return name }
        if fm.fileExists(atPath: dst.path) {
            // keep the old one next to it instead of overwriting
            try? fm.moveItem(at: dst, to: Store.skillsHome.appendingPathComponent(name + ".old-" + Store.dayFormatter.string(from: Date())))
        }
        if isDir.boolValue {
            try fm.copyItem(at: url, to: dst)
        } else {
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: dst.appendingPathComponent("SKILL.md"))
        }
        return name
    }
}

/// «Шаблон из скилла»: a skill made in chat (or received as a folder/.md) becomes a template.
struct SkillTemplateView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var skills: [SkillInfo] = []
    @State private var picked: String?
    @State private var title = ""
    @State private var subtitle = ""
    @State private var error: String?
    @State private var showAll = false

    private var linked: Set<String> { Set(store.templates.compactMap(\.skill)) }
    private var shown: [SkillInfo] {
        skills.filter { !linked.contains($0.name) && (showAll || $0.name.hasPrefix("reels") || $0.name.contains("reel")) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Шаблон из скилла").font(.system(size: 17, weight: .semibold))
                Text("скиллы из ~/.claude/skills, которые ещё не стали шаблонами").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).frame(height: 56)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel("Скиллы")
                        Spacer()
                        Toggle("все", isOn: $showAll).toggleStyle(.checkbox).font(.caption)
                    }
                    ScrollView {
                        VStack(spacing: 6) {
                            if shown.isEmpty {
                                Text("Новых скиллов для рилсов нет. Попроси Claude в чате сохранить стиль как скилл reels-…, или выбери папку ниже.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 20)
                            }
                            ForEach(shown) { s in
                                Button { pick(s) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.name).font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Text(s.description).font(.system(size: 11)).foregroundStyle(Color(hex: "#b4b6bc")).lineLimit(3)
                                    }
                                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(picked == s.name ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(picked == s.name ? Theme.accent : .clear))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button("Выбрать папку скилла или .md…") { importFromDisk() }
                }
                .padding(20).frame(width: 420)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    if let picked {
                        (Text("Скилл: ").foregroundStyle(Theme.muted) + Text(picked).font(.system(size: 13, design: .monospaced)))
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Название шаблона")
                            TextField("Например: Стиль 4. Неон", text: $title).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Подпись")
                            TextField("Одна строка: суть стиля", text: $subtitle).textFieldStyle(.roundedBorder)
                        }
                        Text("Ролики в этом шаблоне Claude будет делать строго по скиллу. Пример можно сделать потом кнопкой «Создать пример» в окне шаблона.")
                            .font(.caption).foregroundStyle(Theme.muted)
                        Spacer()
                        Button(action: save) {
                            Text("Создать шаблон").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40)
                                .foregroundStyle(Color(hex: "#1b1c21")).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Spacer()
                        Text("Выбери скилл слева").foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                        Spacer()
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(Color(hex: "#e0444c")) }
                }
                .padding(20)
                .background(Color(hex: "#17181c"))
            }
        }
        .frame(width: 900, height: 600)
        .background(Theme.panel)
        .onAppear { skills = Skills.all() }
    }

    private func pick(_ s: SkillInfo) {
        picked = s.name
        let base = s.name.replacingOccurrences(of: "reels-", with: "").replacingOccurrences(of: "-", with: " ")
        title = base.prefix(1).uppercased() + base.dropFirst()
        subtitle = String(s.description.split(separator: ".").first ?? "").trimmingCharacters(in: .whitespaces)
        error = nil
    }

    private func importFromDisk() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = false
        p.allowedContentTypes = [.folder, UTType(filenameExtension: "md") ?? .plainText]
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let name = try Skills.importSkill(from: url)
            skills = Skills.all()
            if let s = skills.first(where: { $0.name == name }) { pick(s) }
        } catch { self.error = "Не получилось взять скилл: \(error.localizedDescription)" }
    }

    private func save() {
        guard let picked else { return }
        let name = title.trimmingCharacters(in: .whitespaces)
        let short = String(Store.fileSafe(picked.replacingOccurrences(of: "reels-", with: "")).filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(16))
        let t = ReelTemplate(id: "custom-" + UUID().uuidString.prefix(8).lowercased(), name: name, subtitle: subtitle, short: short.isEmpty ? "Custom" : short,
                             skill: picked, instructions: "", reference: nil, facts: nil, builtIn: false,
                             stripHeight: 1, stripHex: "#3c4250", word: "Run", wordHex: "#ffffff")
        store.saveTemplate(t)
        store.backupSkill(picked)
        dismiss()
    }
}
