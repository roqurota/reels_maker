import SwiftUI

struct JournalView: View {
    @Environment(Store.self) private var store
    @State private var filter = "all"
    @State private var songFilter = "Все песни"

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMM yyyy"; return f
    }()

    private var rows: [ReelEntry] {
        store.journal.filter { e in
            (filter == "all" || (filter == "pub" ? e.published : !e.published))
                && (songFilter == "Все песни" || e.song == songFilter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text("Журнал роликов").font(.system(size: 18, weight: .semibold))
                Text("_studio/reels.json").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button("Найти ролики в папках") { importExisting() }
                    .help("Добавить в журнал mp4 из папок дней, которых в нём ещё нет")
            }
            .padding(.horizontal, 24).frame(height: 60)
            Divider()

            HStack(spacing: 12) {
                stat("Всего роликов", "\(store.journal.count)", Theme.text)
                stat("Опубликовано", "\(store.journal.filter(\.published).count)", Color(hex: "#8fd4a6"))
                stat("Ждут публикации", "\(store.journal.filter { !$0.published }.count)", Color(hex: "#f0a66b"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("По песням").font(.caption).foregroundStyle(Theme.muted)
                    Text(bySong).font(.system(size: 12)).lineLimit(2)
                }
                .padding(14).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24).padding(.top, 18)

            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    Text("Все").tag("all"); Text("Не опубликованы").tag("unpub"); Text("Опубликованы").tag("pub")
                }
                .pickerStyle(.segmented).frame(width: 360).labelsHidden()
                Picker("", selection: $songFilter) {
                    Text("Все песни").tag("Все песни")
                    ForEach(Array(Set(store.journal.map(\.song))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 200).labelsHidden()
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 14)

            Table(rows) {
                TableColumn("Дата") { e in Text(Self.df.string(from: e.date)).foregroundStyle(Theme.muted) }.width(100)
                TableColumn("Название") { e in
                    Text(URL(fileURLWithPath: e.file).lastPathComponent).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(FileManager.default.fileExists(atPath: e.file) ? Theme.text : Theme.muted)
                }
                TableColumn("Песня") { e in Text(e.song) }.width(120)
                TableColumn("Часть") { e in Text(e.part) }.width(90)
                TableColumn("Шаблон") { e in Text(e.template) }.width(120)
                TableColumn("Статус") { e in
                    Button { toggle(e) } label: {
                        Text(e.published ? "Опубликован" : "Не опубликован").font(.system(size: 12))
                            .padding(.horizontal, 10).frame(height: 24)
                            .foregroundStyle(e.published ? Color(hex: "#bfe8cc") : Color(hex: "#f0c49a"))
                            .background(e.published ? Color(hex: "#1f3326") : .clear, in: Capsule())
                            .overlay(Capsule().stroke(e.published ? Color(hex: "#3f7a52") : Color(hex: "#5a4a3a")))
                    }
                    .buttonStyle(.plain)
                }.width(140)
            }
            .contextMenu(forSelectionType: ReelEntry.ID.self) { ids in
                if let id = ids.first, let e = store.journal.first(where: { $0.id == id }) {
                    Button("Открыть ролик") { Finder.open(e.file) }
                    Button("Показать в Finder") { Finder.reveal(e.file) }
                    Button("Убрать из журнала", role: .destructive) {
                        store.journal.removeAll { $0.id == id }; store.saveJournal()
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let e = store.journal.first(where: { $0.id == id }) { Finder.open(e.file) }
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    private var bySong: String {
        let counts = Dictionary(grouping: store.journal, by: \.song).mapValues(\.count)
        let s = counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: " · ")
        return s.isEmpty ? "пока пусто" : s
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(color)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggle(_ e: ReelEntry) {
        guard let i = store.journal.firstIndex(where: { $0.id == e.id }) else { return }
        store.journal[i].published.toggle()
        store.saveJournal()
    }

    /// Picks up mp4 files in <root>/<yyyy-MM-dd>/<song>/ that the journal doesn't know yet.
    private func importExisting() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: store.reelsRoot)
        guard let days = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        let known = Set(store.journal.map(\.file))
        for day in days {
            guard let date = Store.dayFormatter.date(from: day) else { continue }
            let dayURL = root.appendingPathComponent(day)
            for songDir in (try? fm.contentsOfDirectory(atPath: dayURL.path)) ?? [] where !songDir.hasPrefix(".") && !songDir.hasPrefix("_") {
                let dir = dayURL.appendingPathComponent(songDir)
                for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.lowercased().hasSuffix(".mp4") || f.lowercased().hasSuffix(".mov") {
                    let path = dir.appendingPathComponent(f).path
                    if known.contains(path) { continue }
                    let bits = (f as NSString).deletingPathExtension.split(separator: "_").map(String.init)
                    let tpl = bits.count > 2 ? (store.templates.first { $0.short == bits[2] }?.name ?? bits[2]) : ""
                    store.journal.append(ReelEntry(date: date, file: path, song: songDir, part: bits.count > 1 ? bits[1] : "", template: tpl))
                }
            }
        }
        store.journal.sort { $0.date > $1.date }
        store.saveJournal()
    }
}
