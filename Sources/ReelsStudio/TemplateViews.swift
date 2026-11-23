import SwiftUI

struct TemplatesView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    @State private var toDelete: ReelTemplate?
    @State private var showArchive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Шаблоны").font(.system(size: 18, weight: .semibold))
                Text("_studio/templates").font(.caption).foregroundStyle(Theme.muted)
                Picker("", selection: $showArchive) {
                    Text("Активные (\(store.activeTemplates.count))").tag(false)
                    Text("Архив (\(store.archivedTemplates.count))").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260).padding(.leading, 12)
                Spacer()
                Button("+ Шаблон из скилла") { nav.showSkillTemplate = true }
                Button("+ Новый шаблон по референсу") { nav.showNewTemplate = true }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).frame(height: 60)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showArchive {
                        Text(store.archivedTemplates.isEmpty ? "Архив пуст" : "Эти шаблоны не показываются в новых заданиях. Вернуть: иконка со стрелкой или правый клик.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12)], spacing: 12) {
                        ForEach(showArchive ? store.archivedTemplates : store.activeTemplates) { t in card(t) }
                    }
                }
                .padding(24)
            }
        }
        .confirmationDialog("Удалить шаблон «\(toDelete?.name ?? "")»? Скилл останется в ~/.claude/skills.", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Удалить", role: .destructive) { if let t = toDelete { store.deleteTemplate(t) }; toDelete = nil }
        }
    }

    private func card(_ t: ReelTemplate) -> some View {
        let archived = t.archived ?? false
        return Card {
            HStack(alignment: .top, spacing: 14) {
                TemplateThumb(t: t, width: 54)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(t.name).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button { nav.previewTemplate = t } label: { Image(systemName: "gearshape") }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Пример и настройки")
                        Button { store.setArchived(t.id, !archived) } label: {
                            Image(systemName: archived ? "arrow.uturn.backward" : "archivebox")
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.muted).help(archived ? "Вернуть из архива" : "Архивировать")
                    }
                    Text(t.subtitle).font(.system(size: 12)).foregroundStyle(Color(hex: "#c4c6cc"))
                    if let skill = t.skill, !skill.isEmpty { Text("скилл: \(skill)").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                    ForEach(t.facts ?? []) { f in
                        (Text(f.k + ": ").foregroundStyle(Theme.muted) + Text(f.v)).font(.system(size: 11))
                    }
                    if let r = t.reference, !r.isEmpty { Text(r).font(.system(size: 11)).foregroundStyle(Theme.accent).lineLimit(1) }
                    Text(t.previewPath == nil ? "Примера пока нет" : "Есть пример")
                        .font(.system(size: 11)).foregroundStyle(t.previewPath == nil ? Theme.muted : Theme.accent)
                }
            }
        }
        .contextMenu {
            Button("Пример и настройки…") { nav.previewTemplate = t }
            Button(archived ? "Вернуть из архива" : "Архивировать") { store.setArchived(t.id, !archived) }
            if !t.builtIn { Divider(); Button("Удалить…", role: .destructive) { toDelete = t } }
        }
    }
}

/// Reference → Claude analysis → editable facts → save (+ optional test reel).
struct NewTemplateView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var reference = ""
    @State private var about = ""
    @State private var files: [String] = []
    @State private var draft: ReelTemplate?
    @State private var testSongId: String?
    @State private var testPart: String?
    @State private var message: String?

    private var analyzeJob: Job? { store.jobs.first { $0.id == store.draftAnalyzeJobId } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Новый шаблон по референсу").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).frame(height: 56)
            Divider()
            HStack(spacing: 0) {
                left.frame(width: 400)
                Divider()
                right
            }
        }
        .frame(width: 1060, height: 800)
        .background(Theme.panel)
        .onAppear { loadDraftIfReady() }
        .onChange(of: analyzeJob?.status) { _, _ in loadDraftIfReady() }
    }

    private var left: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Шаг 1. Дай пример ролика, который нравится. Claude посмотрит его и опишет стиль.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Ссылки на референсы")
                    StyledEditor(text: $reference, placeholder: "https://www.instagram.com/reel/…\nкаждая ссылка с новой строки", minHeight: 60)
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Или файлы")
                    Button { files += Finder.pickFiles() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text(files.isEmpty ? "Выбрать видео или скриншоты" : "Добавить ещё")
                        }
                        .font(.system(size: 12)).frame(maxWidth: .infinity).frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color(hex: "#4a4d55")))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(files, id: \.self) { f in
                        HStack {
                            Text(URL(fileURLWithPath: f).lastPathComponent).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                            Spacer()
                            Button { files.removeAll { $0 == f } } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Что нравится в этом ролике")
                    StyledEditor(text: $about, placeholder: "Например: как слова появляются по одному, тёплый цвет, резкие склейки в бит", minHeight: 100)
                }
                Button {
                    draft = nil
                    store.draftAnalyzeJobId = store.enqueueAnalyze(reference: reference, about: about, files: files)
                } label: {
                    Text(analyzeJob?.status == .running || analyzeJob?.status == .waiting ? "Разбираю…" : (draft == nil ? "Разобрать референс" : "Разобрать заново"))
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 42)
                        .foregroundStyle(Color(hex: "#1b1c21")).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(reference.isEmpty && about.isEmpty && files.isEmpty || analyzeJob?.status == .running)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var right: some View {
        Group {
            if let job = analyzeJob, job.status == .running || job.status == .waiting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(job.status == .waiting ? "Ждёт своей очереди (сначала доделываются ролики)" : "Claude разбирает референс")
                    Text(job.note).font(.caption).foregroundStyle(Theme.muted).lineLimit(2).frame(maxWidth: 400)
                    Text("Окно можно закрыть, разбор продолжится.").font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let job = analyzeJob, job.status == .failed {
                VStack(spacing: 10) {
                    Text("Разбор не получился").font(.title3)
                    Text(job.log.suffix(3).joined(separator: "\n")).font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if draft != nil {
                editor
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle").font(.system(size: 36)).foregroundStyle(Color(hex: "#5a5d66"))
                    Text("Здесь появится разбор стиля").font(.system(size: 14))
                    Text("Формат, цвет, титры, темп склеек, эффекты и чем это лучше делать.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(hex: "#17181c"))
    }

    @ViewBuilder
    private var editor: some View {
        if let binding = Binding($draft) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Шаг 2. Проверь разбор, поправь, если что-то не так").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(binding.facts.wrappedValue?.indices ?? 0..<0, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel(binding.wrappedValue.facts?[i].k ?? "")
                                TextField("", text: Binding(get: { draft?.facts?[i].v ?? "" }, set: { draft?.facts?[i].v = $0 }), axis: .vertical)
                                    .textFieldStyle(.plain).font(.system(size: 13))
                            }
                            .padding(12).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Описание стиля для монтажа")
                        StyledEditor(text: binding.instructions, placeholder: "", minHeight: 90)
                    }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Название шаблона")
                            TextField("", text: binding.name).textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Тестовый ролик на")
                            HStack {
                                Picker("", selection: $testSongId) {
                                    ForEach(store.songs.filter { !$0.parts.isEmpty }) { Text($0.name).tag(Optional($0.id)) }
                                }.labelsHidden()
                                Picker("", selection: $testPart) {
                                    ForEach(store.song(testSongId)?.parts ?? []) { Text($0.name).tag(Optional($0.name)) }
                                }.labelsHidden()
                            }
                        }
                    }
                    if let message {
                        Text(message).font(.system(size: 12)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "#1f3326"), in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: 10) {
                        Button { save(test: false) } label: {
                            Text("Сохранить без теста").frame(maxWidth: .infinity).frame(height: 40)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#34373e")))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { save(test: true) } label: {
                            Text("Сохранить и сделать тестовый ролик").font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .foregroundStyle(Color(hex: "#1b1c21")).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(testPart == nil)
                    }
                }
                .padding(24)
            }
        }
    }

    private func loadDraftIfReady() {
        if testSongId == nil {
            let s = store.songs.first { !$0.parts.isEmpty }
            testSongId = s?.id
            testPart = s?.parts.first { $0.name.hasPrefix("Chorus") }?.name ?? s?.parts.first?.name
        }
        guard draft == nil, let job = analyzeJob, job.status == .done else { return }
        let url = URL(fileURLWithPath: job.workDir).appendingPathComponent("template.json")
        guard let data = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let name = o["name"] as? String ?? "Новый стиль"
        let facts = (o["facts"] as? [[String: Any]] ?? []).compactMap { d -> Fact? in
            guard let k = d["k"] as? String, let v = d["v"] as? String else { return nil }
            return Fact(k: k, v: v)
        }
        let id = "custom-" + UUID().uuidString.prefix(8).lowercased()
        draft = ReelTemplate(id: id, name: name, subtitle: o["subtitle"] as? String ?? "", short: Store.fileSafe(name).filter { $0.isLetter || $0.isNumber }.prefix(14).description,
                             skill: (o["skill"] as? String).flatMap { $0.isEmpty ? nil : $0 }, instructions: o["instructions"] as? String ?? "",
                             reference: reference.isEmpty ? nil : reference, facts: facts, builtIn: false,
                             stripHeight: 1, stripHex: o["stripHex"] as? String ?? "#3c4250", word: "Run", wordHex: "#ffffff")
        if let notes = o["notes"] as? String, !notes.isEmpty { message = "Claude: " + notes }
    }

    private func save(test: Bool) {
        guard var t = draft else { return }
        if t.short.isEmpty { t.short = "Custom" }
        store.saveTemplate(t)
        if test, let song = store.song(testSongId), let part = testPart {
            _ = store.enqueueReels(song: song, picks: [(part, t.id)], variants: 1, moods: song.moods, colors: song.colors, wishes: "Это тестовый ролик нового шаблона.")
            message = "Шаблон сохранён, тестовый ролик в очереди. Не понравится: поправь через «Доработать» в очереди."
        } else {
            message = "Шаблон сохранён и появился в списке."
        }
        store.draftAnalyzeJobId = nil
        draft = nil
        dismiss()
    }
}

struct SettingsView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Папки") {
                HStack {
                    TextField("Папка рилсов", text: $store.reelsRoot)
                    Button("Выбрать…") { if let p = Finder.pickFolder(start: store.reelsRoot) { store.reelsRoot = p; store.load() } }
                }
                HStack {
                    TextField("Папка песен", text: $store.songsRoot)
                    Button("Выбрать…") { if let p = Finder.pickFolder(start: store.songsRoot) { store.songsRoot = p } }
                }
            }
            Section("Claude") {
                TextField("Путь к claude", text: $store.claudePath)
                Picker("Разрешения", selection: $store.permissionMode) {
                    Text("auto: Claude сам решает, что безопасно").tag("auto")
                    Text("acceptEdits: только правки файлов").tag("acceptEdits")
                    Text("bypassPermissions: всё без вопросов").tag("bypassPermissions")
                }
                TextField("Модель (пусто = по умолчанию)", text: $store.model)
            }
            Section {
                Button("Перечитать данные с диска") { store.load() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 420)
    }
}
