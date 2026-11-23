import SwiftUI

struct NewTaskView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    @State private var songId: String?
    @State private var search = ""
    @State private var enabledParts: [String] = []
    @State private var partTemplates: [String: [String]] = [:]
    @State private var moodOff: Set<String> = []
    @State private var colorOff: Set<String> = []
    @State private var wishes = ""
    @State private var variants = 1
    @State private var sentText: String?
    @State private var media: [String] = []
    @State private var usePexels = true
    @State private var showArchive = false

    private var song: Song? { store.song(songId) ?? store.songs.first }

    private var picks: [(part: String, templateId: String)] {
        guard let song else { return [] }
        var out: [(String, String)] = []
        for p in song.parts where enabledParts.contains(p.name) {
            for t in store.activeTemplates where (partTemplates[p.name] ?? []).contains(t.id) { out.append((p.name, t.id)) }
        }
        return out
    }

    private var plannedFiles: [String] {
        guard let song else { return [] }
        var files: [String] = []
        for pick in picks {
            guard let t = store.template(pick.templateId) else { continue }
            for v in 1...variants { files.append(store.plannedFileName(song: song, part: pick.part, template: t, variant: v)) }
        }
        return files
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                songList.frame(width: 230)
                Divider()
                center
                Divider()
                rightPanel.frame(width: 300)
            }
        }
        .onAppear { if songId == nil, let first = store.songs.first { select(first) } }
        .onChange(of: song) { _, s in if let s { media = s.media; usePexels = s.pexels } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("Новое задание").font(.system(size: 18, weight: .semibold))
            Label("Папка дня: \(URL(fileURLWithPath: store.reelsRoot).lastPathComponent) / \(Store.dayFormatter.string(from: Date()))", systemImage: "folder")
                .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
            Spacer()
            Text("Сегодня сделано: \(pluralReels(store.madeToday))").font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 24).frame(height: 60)
    }

    // MARK: Songs column

    private var songList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Песни")
                TextField("Поиск", text: $search).textFieldStyle(.roundedBorder)
            }
            .padding(14)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.songs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { s in
                        songRow(s)
                    }
                }
                .padding(.horizontal, 8)
            }
            Divider()
            Button { nav.editingSong = Song.newEmpty() } label: {
                Text("+ Добавить песню").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 34)
                    .foregroundStyle(Theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(12)
        }
    }

    private func songRow(_ s: Song) -> some View {
        let selected = s.id == song?.id
        let made = store.madeCount(song: s)
        return Button { select(s) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.name).font(.system(size: 13, weight: .medium))
                    HStack(spacing: 3) {
                        ForEach(s.colors.prefix(4), id: \.self) { c in Circle().fill(Color(hex: Palette.tag(c).hex)).frame(width: 8, height: 8) }
                        Text(s.parts.isEmpty ? "нет титров" : "\(s.release) · \(s.parts.count) ч.")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.leading, s.colors.isEmpty ? 0 : 3)
                    }
                }
                Spacer()
                if made > 0 { Text("\(made) шт").font(.system(size: 11)).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? Color(hex: "#2a2c33") : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ s: Song) {
        songId = s.id
        let first = s.parts.first { $0.name.hasPrefix("Chorus") } ?? s.parts.first
        enabledParts = first.map { [$0.name] } ?? []
        partTemplates = [:]
        moodOff = []; colorOff = []
        media = s.media; usePexels = s.pexels
        sentText = nil
    }

    // MARK: Center

    @ViewBuilder private var center: some View {
        if let song {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(song.name).font(.system(size: 24, weight: .bold))
                        Text(song.release).foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Изменить карточку песни") { nav.editingSong = song }.buttonStyle(.link)
                    }
                    songCard(song)
                    MediaPicker(folders: $media, usePexels: $usePexels,
                                hint: "Из карточки песни. Для этого задания можно поменять, карточка не изменится.",
                                startFolder: song.folder)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Части и шаблоны", hint: "у каждой части свои шаблоны")
                        if song.parts.isEmpty {
                            Card { Text("В папке песни нет Titles. Сделай титры отдельно (song-srt), части появятся сами.").foregroundStyle(Theme.muted) }
                        }
                        ForEach(song.parts) { p in partRow(p) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Пожелания для Claude")
                        StyledEditor(text: $wishes, placeholder: "Например: больше ночного города, склейка на каждом слове, титры крупнее", minHeight: 60)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
            }
        } else {
            VStack(spacing: 12) {
                Text("Песен пока нет").font(.title3)
                Button("Добавить песню") { nav.editingSong = Song.newEmpty() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func songCard(_ song: Song) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(song.description.isEmpty ? "Описания пока нет. Добавь его в карточке песни: Claude опирается на него при подборе футажей." : song.description)
                    .font(.system(size: 13)).lineSpacing(3)
                    .foregroundStyle(song.description.isEmpty ? Theme.muted : Color(hex: "#d4d6db"))
                if !song.moods.isEmpty || !song.colors.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(song.moods, id: \.self) { m in
                            Chip(label: m, on: !moodOff.contains(m), strikeWhenOff: true) { toggle(&moodOff, m) }
                        }
                        ForEach(song.colors, id: \.self) { c in
                            ColorChip(tag: Palette.tag(c), on: !colorOff.contains(c), showName: false) { toggle(&colorOff, c) }
                        }
                    }
                    Text("Из карточки песни. Для этого задания можно снять теги и цвета, карточка не изменится.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func partRow(_ p: SongPart) -> some View {
        let on = enabledParts.contains(p.name)
        return Card(highlight: on) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if on { enabledParts.removeAll { $0 == p.name } } else { enabledParts.append(p.name) }
                    sentText = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 17))
                            .foregroundStyle(on ? Theme.accent : Theme.muted)
                        Text(p.name).font(.system(size: 13, weight: .semibold)).frame(width: 96, alignment: .leading)
                        Text(p.durationText).font(.system(size: 11)).foregroundStyle(Theme.muted).frame(width: 36, alignment: .leading)
                        Text(p.firstLine ?? "").font(.system(size: 12)).foregroundStyle(Color(hex: "#b4b6bc")).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if on {
                    FlowLayout(spacing: 6) {
                        ForEach(store.activeTemplates) { t in
                            let chosen = partTemplates[p.name] ?? []
                            Chip(label: t.name, on: chosen.contains(t.id), square: true) {
                                var c = chosen
                                if c.contains(t.id) { c.removeAll { $0 == t.id } } else { c.append(t.id) }
                                partTemplates[p.name] = c
                                sentText = nil
                            }
                        }
                    }
                    .padding(.leading, 30)
                }
            }
        }
    }

    /// true when every checked part already has this template
    private func templateOnAllParts(_ id: String) -> Bool {
        !enabledParts.isEmpty && enabledParts.allSatisfy { (partTemplates[$0] ?? []).contains(id) }
    }

    private func toggleForEnabledParts(_ id: String) {
        let remove = templateOnAllParts(id)
        for p in enabledParts {
            var c = partTemplates[p] ?? []
            if remove { c.removeAll { $0 == id } } else if !c.contains(id) { c.append(id) }
            partTemplates[p] = c
        }
        sentText = nil
    }

    private func removeFromParts(_ id: String) {
        for k in partTemplates.keys { partTemplates[k]?.removeAll { $0 == id } }
    }

    private func toggle(_ set: inout Set<String>, _ v: String) {
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
        sentText = nil
    }

    // MARK: Right panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $showArchive) {
                        Text("Шаблоны").tag(false)
                        Text("Архив (\(store.archivedTemplates.count))").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if showArchive {
                        if store.archivedTemplates.isEmpty {
                            Text("Архив пуст").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.vertical, 8)
                        }
                        ForEach(store.archivedTemplates) { t in
                            HStack(spacing: 10) {
                                TemplateThumb(t: t, width: 30).opacity(0.6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.system(size: 12, weight: .semibold))
                                    Text(t.subtitle).font(.system(size: 11)).foregroundStyle(Color(hex: "#a9abb2")).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Button("Вернуть") { store.setArchived(t.id, false) }
                                    .font(.system(size: 11))
                            }
                            .padding(8)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                            .contextMenu {
                                Button("Вернуть из архива") { store.setArchived(t.id, false) }
                                Button("Пример и настройки…") { nav.previewTemplate = t }
                            }
                        }
                    } else {
                    Text("Клик ставит шаблон отмеченным частям").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    ForEach(store.activeTemplates) { t in
                        let on = templateOnAllParts(t.id)
                        HStack(spacing: 6) {
                            Button { toggleForEnabledParts(t.id) } label: {
                                HStack(spacing: 10) {
                                    TemplateThumb(t: t, width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).font(.system(size: 12, weight: .semibold))
                                        Text(t.subtitle).font(.system(size: 11)).foregroundStyle(Color(hex: "#a9abb2")).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Поставить этот шаблон всем отмеченным частям")
                            Button { nav.previewTemplate = t } label: {
                                Image(systemName: "gearshape").font(.system(size: 13)).frame(width: 26, height: 26).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted)
                            .help("Пример и настройки шаблона")
                        }
                        .padding(8)
                        .background(on ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : .clear))
                        .contextMenu {
                            Button("Пример и настройки…") { nav.previewTemplate = t }
                            Button("Архивировать") { store.setArchived(t.id, true); removeFromParts(t.id) }
                        }
                    }
                    }
                    Button("+ Шаблон из скилла") { nav.showSkillTemplate = true }
                        .buttonStyle(.link).font(.system(size: 12)).frame(maxWidth: .infinity)
                    Button { nav.showNewTemplate = true } label: {
                        Text("+ Новый шаблон по референсу").font(.system(size: 13)).frame(maxWidth: .infinity).frame(height: 38)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color(hex: "#5a5d66")))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Stepper(value: $variants, in: 1...5) {
                    Text("Вариантов на каждую пару: \(variants)").font(.system(size: 12))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Сохранится в \(Store.dayFormatter.string(from: Date())) / \(song?.name ?? "")").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    ForEach(plannedFiles.prefix(4), id: \.self) { f in
                        Text(f).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(hex: "#b4b6bc")).lineLimit(1).truncationMode(.middle)
                    }
                    if plannedFiles.count > 4 { Text("и ещё \(plannedFiles.count - 4)").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 8))
                if let sentText {
                    HStack {
                        Text(sentText).font(.system(size: 12))
                        Spacer()
                        Button("Очередь") { nav.screen = .queue }.buttonStyle(.link)
                    }
                    .padding(10).background(Color(hex: "#1f3326"), in: RoundedRectangle(cornerRadius: 8))
                }
                Button(action: send) {
                    Text(plannedFiles.isEmpty ? "Выбери часть и шаблон" : "Отправить Claude · \(pluralReels(plannedFiles.count))")
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 42)
                        .foregroundStyle(plannedFiles.isEmpty ? Theme.muted : Color(hex: "#1b1c21"))
                        .background(plannedFiles.isEmpty ? Color(hex: "#2a2c33") : Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(plannedFiles.isEmpty || !store.rootAvailable)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
            .background(Theme.panel)
        }
        .background(Color(hex: "#17181c"))
    }

    private func send() {
        guard let song else { return }
        let n = store.enqueueReels(song: song, picks: picks, variants: variants,
                                   moods: song.moods.filter { !moodOff.contains($0) },
                                   colors: song.colors.filter { !colorOff.contains($0) },
                                   wishes: wishes.trimmingCharacters(in: .whitespacesAndNewlines),
                                   mediaFolders: media, usePexels: usePexels)
        sentText = "Добавлено в очередь: \(pluralReels(n))"
    }
}
