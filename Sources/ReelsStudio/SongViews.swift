import SwiftUI

struct SongsView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Песни").font(.system(size: 18, weight: .semibold))
                Text("_studio/songs.json").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button("Перечитать папки") { store.load() }
                Button("+ Добавить песню") { nav.editingSong = Song.newEmpty() }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).frame(height: 60)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(store.songs) { s in
                        Button { nav.editingSong = s } label: {
                            Card {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(s.name).font(.system(size: 15, weight: .semibold))
                                        Text(s.release).font(.caption).foregroundStyle(Theme.muted)
                                        Spacer()
                                        ForEach(s.colors, id: \.self) { c in Circle().fill(Color(hex: Palette.tag(c).hex)).frame(width: 10, height: 10) }
                                    }
                                    Text(s.description.isEmpty ? "Нет описания" : s.description)
                                        .font(.system(size: 12)).foregroundStyle(s.description.isEmpty ? Theme.muted : Color(hex: "#c4c6cc")).lineLimit(3)
                                    Text(s.parts.isEmpty ? "Нет титров" : s.parts.map(\.name).joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    if !s.moods.isEmpty { Text(s.moods.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Theme.accent) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
    }
}

struct SongEditorView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var song: Song
    @State private var customMood = ""
    @State private var customColor = Color(hex: "#888888")
    @State private var confirmDelete = false

    private var isNew: Bool { !store.songs.contains { $0.id == song.id } }
    private var parts: [SongPart] { Store.detectParts(folder: song.folder) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "Новая песня" : "Карточка песни").font(.system(size: 17, weight: .semibold))
                Text("сохраняется в Библиотеку песен (songs.json)").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 24).frame(height: 56)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        field("Название") { TextField("Например: Icon", text: $song.name).textFieldStyle(.roundedBorder) }
                        field("Релиз") { TextField("Сингл или EP", text: $song.release).textFieldStyle(.roundedBorder) }.frame(width: 200)
                    }
                    field("Папка песни") {
                        HStack {
                            Text(song.folder.isEmpty ? "не выбрана" : song.folder)
                                .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).frame(height: 30)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
                            Button("Выбрать…") {
                                if let p = Finder.pickFolder(start: song.folder.isEmpty ? store.songsRoot : song.folder) {
                                    song.folder = p
                                    if song.name.isEmpty { song.name = URL(fileURLWithPath: p).lastPathComponent }
                                }
                            }
                        }
                    }
                    if !song.folder.isEmpty {
                        if parts.isEmpty {
                            Text("В папке нет Titles. Песню можно сохранить сейчас, части появятся сами, когда сделаешь титры отдельно (song-srt).")
                                .font(.system(size: 12)).foregroundStyle(Color(hex: "#f5c49a"))
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: "#2a2117"), in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Найдено в Titles: \(parts.count) ч.").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "#bfe8cc"))
                                ForEach(parts) { p in
                                    Text("✓ \(p.name) · \(p.durationText) · \(p.wav != nil ? "WAV + SRT" : "только SRT")").font(.system(size: 12))
                                }
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "#172219"), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    field("Описание: о чём песня") {
                        StyledEditor(text: $song.description, placeholder: "Идея, история, образы. Claude опирается на это при подборе футажей и эффектов.", minHeight: 90)
                    }
                    field("Настроение") {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(Set(Palette.moods + song.moods)).sorted { (Palette.moods.firstIndex(of: $0) ?? 99, $0) < (Palette.moods.firstIndex(of: $1) ?? 99, $1) }, id: \.self) { m in
                                Chip(label: m, on: song.moods.contains(m)) {
                                    if song.moods.contains(m) { song.moods.removeAll { $0 == m } } else { song.moods.append(m) }
                                }
                            }
                            TextField("+ своё", text: $customMood)
                                .textFieldStyle(.plain).font(.system(size: 12)).frame(width: 100, height: 28).padding(.horizontal, 10)
                                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color(hex: "#4a4d55")))
                                .onSubmit {
                                    let m = customMood.trimmingCharacters(in: .whitespaces).lowercased()
                                    if !m.isEmpty && !song.moods.contains(m) { song.moods.append(m) }
                                    customMood = ""
                                }
                        }
                    }
                    field("Цвета", hint: "можно несколько") {
                        FlowLayout(spacing: 8) {
                            ForEach(Palette.all + song.colors.filter { $0.hasPrefix("#") }.map { Palette.tag($0) }) { tag in
                                ColorChip(tag: tag, on: song.colors.contains(tag.id)) {
                                    if song.colors.contains(tag.id) { song.colors.removeAll { $0 == tag.id } } else { song.colors.append(tag.id) }
                                }
                            }
                            HStack(spacing: 6) {
                                ColorPicker("", selection: $customColor, supportsOpacity: false).labelsHidden()
                                Button("+ свой цвет") {
                                    let hex = customColor.hexString
                                    if !song.colors.contains(hex) { song.colors.append(hex) }
                                }
                                .buttonStyle(.plain).font(.system(size: 12))
                            }
                            .padding(.horizontal, 8).frame(height: 30)
                            .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color(hex: "#4a4d55")))
                        }
                    }
                    MediaPicker(folders: Binding(get: { song.media }, set: { song.mediaFolders = $0 }),
                                usePexels: Binding(get: { song.pexels }, set: { song.usePexels = $0 }),
                                hint: "По умолчанию для всех рилсов этой песни. В задании можно поменять.")
                    field("Ссылки (необязательно)") {
                        TextField("Лирика в Google Docs, демо, референсы", text: $song.links).textFieldStyle(.roundedBorder)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                if !isNew {
                    Button("Удалить песню", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить в библиотеку") {
                    if isNew && !store.songs.contains(where: { $0.id == song.name }) { song.id = song.name }
                    store.upsert(song)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(song.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 760, height: 820)
        .background(Theme.panel)
        .confirmationDialog("Удалить «\(song.name)» из библиотеки? Файлы песни на диске останутся.", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { store.delete(song); dismiss() }
        }
    }

    private func field<C: View>(_ label: String, hint: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label, hint: hint)
            content()
        }
    }
}
