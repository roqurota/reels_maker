import SwiftUI
import AVFoundation

/// First frame-ish thumbnail of a reel, cached.
struct VideoThumb: View {
    let path: String
    var width: CGFloat = 54
    @State private var image: NSImage?
    @MainActor static var cache: [String: NSImage] = [:]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.black)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "film").foregroundStyle(Theme.muted) }
        }
        .frame(width: width, height: width * 16 / 9)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: path) { await load() }
    }

    private func load() async {
        if let c = VideoThumb.cache[path] { image = c; return }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 428)
        if let cg = try? await gen.image(at: CMTime(seconds: 2, preferredTimescale: 600)).image {
            let img = NSImage(cgImage: cg, size: .zero)
            VideoThumb.cache[path] = img
            image = img
        }
    }
}

struct PublishView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    @State private var selected: [UUID] = []
    @State private var onlyUnpublished = true
    @State private var generating: Set<UUID> = []
    @State private var genError: [UUID: String] = [:]
    @State private var dryRun = false
    @State private var sent: String?
    @AppStorage("captionLanguage") private var language = "English"

    private var entries: [ReelEntry] {
        store.journal.filter { (!onlyUnpublished || !$0.published) && FileManager.default.fileExists(atPath: $0.file) }
    }

    private var ready: Bool {
        !selected.isEmpty && selected.allSatisfy { id in
            let d = store.drafts[id] ?? PublishDraft()
            return !d.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && d.privacy != nil && d.caption.count <= TikTok.captionLimit
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Публикация").font(.system(size: 18, weight: .semibold))
                Label("TikTok", systemImage: "music.note").font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.card, in: Capsule())
                Spacer()
                Picker("Язык подписей", selection: $language) {
                    Text("English").tag("English"); Text("Русский").tag("Русский")
                }
                .frame(width: 210)
            }
            .padding(.horizontal, 24).frame(height: 60)
            Divider()
            HStack(spacing: 0) {
                reelList.frame(width: 300)
                Divider()
                VStack(spacing: 0) {
                    cards
                    Divider()
                    footer
                }
            }
        }
    }

    // MARK: left: pick reels

    private var reelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Ролики", hint: "\(selected.count) выбрано")
                Toggle("Только неопубликованные", isOn: $onlyUnpublished).toggleStyle(.checkbox).font(.system(size: 12))
            }
            .padding(14)
            ScrollView {
                LazyVStack(spacing: 4) {
                    if entries.isEmpty {
                        Text("Готовых роликов нет. Они появляются здесь из Журнала.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding()
                    }
                    ForEach(entries) { e in row(e) }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func row(_ e: ReelEntry) -> some View {
        let on = selected.contains(e.id)
        return Button {
            if on { selected.removeAll { $0 == e.id } } else { selected.append(e.id) }
            sent = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Theme.accent : Theme.muted)
                VideoThumb(path: e.file, width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(e.song) · \(e.part)").font(.system(size: 12, weight: .semibold))
                    Text(e.template).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    if e.published { Text("Опубликован \(e.platforms)").font(.system(size: 10)).foregroundStyle(Theme.good) }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(on ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: center: one card per chosen reel

    private func draft(_ id: UUID) -> Binding<PublishDraft> {
        Binding(get: { store.drafts[id] ?? PublishDraft() },
                set: { store.drafts[id] = $0; store.saveDrafts() })
    }

    private var cards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if selected.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "paperplane").font(.system(size: 30)).foregroundStyle(Theme.muted)
                        Text("Отметь слева ролики для публикации").foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 120)
                }
                ForEach(selected, id: \.self) { id in
                    if let e = store.journal.first(where: { $0.id == id }) { card(e) }
                }
            }
            .padding(20)
        }
    }

    private func card(_ e: ReelEntry) -> some View {
        let d = draft(e.id)
        return Card {
            HStack(alignment: .top, spacing: 16) {
                Button { Finder.open(e.file) } label: {
                    ZStack {
                        VideoThumb(path: e.file, width: 110)
                        Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .buttonStyle(.plain).help("Открыть ролик")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(e.song) · \(e.part) · \(e.template)").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(d.wrappedValue.caption.count) / \(TikTok.captionLimit)").font(.system(size: 11))
                            .foregroundStyle(d.wrappedValue.caption.count > TikTok.captionLimit ? Color(hex: "#e0444c") : Theme.muted)
                    }
                    StyledEditor(text: d.caption, placeholder: "Подпись с хештегами. Ссылки в TikTok не кликабельны.", minHeight: 70)
                    HStack(spacing: 8) {
                        Button(d.wrappedValue.variants.isEmpty ? "Сгенерировать описание" : "Другие варианты") { generate(e) }
                            .disabled(generating.contains(e.id))
                        if generating.contains(e.id) { ProgressView().controlSize(.small); Text("Claude пишет…").font(.caption).foregroundStyle(Theme.muted) }
                        if let err = genError[e.id] { Text(err).font(.caption).foregroundStyle(Color(hex: "#e0444c")).lineLimit(1) }
                    }
                    ForEach(d.wrappedValue.variants, id: \.self) { v in
                        Button { d.wrappedValue.caption = v } label: {
                            Text(v).font(.system(size: 12)).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(d.wrappedValue.caption == v ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(d.wrappedValue.caption == v ? Theme.accent : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("Взять этот вариант")
                    }
                    Divider()
                    HStack(spacing: 14) {
                        Picker("Кто видит", selection: d.privacy) {
                            Text("Выбери…").tag(String?.none)
                            ForEach(TikTok.privacyOptions, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        .frame(width: 210)
                        Toggle("Комментарии", isOn: d.allowComments)
                        Toggle("Дуэты", isOn: d.allowDuet)
                        Toggle("Стежки", isOn: d.allowStitch)
                    }
                    .toggleStyle(.checkbox).font(.system(size: 12))
                    HStack(spacing: 14) {
                        Picker("Звук", selection: Binding(get: { d.wrappedValue.soundMode ?? "link" }, set: { d.wrappedValue.soundMode = $0 })) {
                            Text("Из ролика, трек «\(e.song)» на 0 для ссылки").tag("link")
                            Text("Официальный трек звучит").tag("track")
                        }
                        .frame(width: 330)
                        .help("«Из ролика»: слышно наш звук, а трек стоит на громкости 0, чтобы у видео была ссылка на песню и кнопка Spotify")
                        if !d.wrappedValue.linkOnly {
                            HStack(spacing: 6) {
                                Text("с").font(.system(size: 12))
                                TextField("авто", text: d.soundStart).textFieldStyle(.roundedBorder).frame(width: 60)
                                    .help("С какого места песни начать трек, м:сс. Пусто: Claude подберёт по части \(e.part)")
                            }
                        }
                    }
                    HStack(spacing: 14) {
                        HStack(spacing: 6) {
                            Text("Обложка, с").font(.system(size: 12))
                            TextField("авто", text: d.coverSec).textFieldStyle(.roundedBorder).frame(width: 50)
                        }
                        Toggle("Метка «создано ИИ»", isOn: d.aiLabel).toggleStyle(.checkbox).font(.system(size: 12))
                    }
                }
            }
        }
    }

    // MARK: bottom bar

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("Сгенерировать всем без подписи") {
                    for id in selected where (store.drafts[id]?.caption ?? "").isEmpty {
                        if let e = store.journal.first(where: { $0.id == id }) { generate(e) }
                    }
                }
                .disabled(selected.isEmpty)
                Spacer()
                Toggle("Только проверка: всё заполнить, но не нажимать «Опубликовать»", isOn: $dryRun)
                    .toggleStyle(.checkbox).font(.system(size: 12))
            }
            HStack(spacing: 12) {
                Text("Публикуя, ты соглашаешься с Music Usage Confirmation TikTok. Ролики публикуются по одному в твоём Chrome, на каждый уходит несколько минут. Во время загрузки буфер обмена занят роликом.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                if let sent {
                    Text(sent).font(.system(size: 12)).foregroundStyle(Theme.good)
                    Button("Очередь") { nav.screen = .queue }.buttonStyle(.link)
                }
                Button {
                    let n = store.enqueuePublish(entryIds: selected, dryRun: dryRun)
                    sent = dryRun ? "Проверка в очереди: \(n)" : "В очереди на публикацию: \(n)"
                } label: {
                    Text(dryRun ? "Проверить (\(selected.count))" : "Опубликовать (\(selected.count))")
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 22).frame(height: 40)
                        .foregroundStyle(ready ? Color(hex: "#1b1c21") : Theme.muted)
                        .background(ready ? Theme.accent : Color(hex: "#2a2c33"), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!ready)
                .help(ready ? "" : "У каждого ролика нужна подпись и выбор «Кто видит»")
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    private func generate(_ e: ReelEntry) {
        generating.insert(e.id); genError[e.id] = nil
        let current = store.drafts[e.id]?.caption ?? ""
        let prompt = Prompts.captions(entry: e, song: store.songs.first { $0.name == e.song }, current: current, language: language)
        Task {
            let r = await ClaudeOnce.run(prompt, store: store)
            generating.remove(e.id)
            switch r {
            case .success(let text):
                let vs = ClaudeOnce.strings(from: text)
                if vs.isEmpty { genError[e.id] = "Не получилось разобрать ответ"; return }
                var d = store.drafts[e.id] ?? PublishDraft()
                d.variants = vs
                if d.caption.isEmpty { d.caption = vs[0] }
                store.drafts[e.id] = d
                store.saveDrafts()
            case .failure(let err):
                genError[e.id] = err.localizedDescription
            }
        }
    }
}
