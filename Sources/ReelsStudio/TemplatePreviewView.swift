import SwiftUI
import AVKit

/// AppKit player; SwiftUI's VideoPlayer fails to load in a plain SwiftPM app bundle.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .floating
        v.videoGravity = .resizeAspect
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

/// Popup for one template: plays its example reel and can make a new example on a chosen song.
struct TemplatePreviewView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    @Environment(\.dismiss) private var dismiss
    let templateId: String

    @State private var player: AVPlayer?
    @State private var songId: String?
    @State private var part: String?
    @State private var change = ""

    private var editJob: Job? {
        store.jobs.last { $0.kind == .skillEdit && $0.templateId == templateId }
    }

    private var t: ReelTemplate? { store.template(templateId) }
    private var exampleJob: Job? {
        store.jobs.last { $0.previewFor == templateId && ($0.status == .waiting || $0.status == .running) }
    }
    private var hasPreview: Bool {
        guard let p = t?.previewPath else { return false }
        return FileManager.default.fileExists(atPath: p)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t?.name ?? "Шаблон").font(.system(size: 17, weight: .semibold))
                Text(t?.subtitle ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                if let t {
                    let archived = t.archived ?? false
                    Button(archived ? "Вернуть из архива" : "Архивировать") {
                        store.setArchived(t.id, !archived)
                        if !archived { player?.pause(); dismiss() }
                    }
                }
                Button("Закрыть") { player?.pause(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).frame(height: 56)
            Divider()
            HStack(alignment: .top, spacing: 24) {
                videoBox
                info
            }
            .padding(24)
        }
        .frame(width: 900, height: 700)
        .background(Theme.panel)
        .onAppear {
            loadPlayer()
            if songId == nil {
                let s = store.songs.first { !$0.parts.isEmpty }
                songId = s?.id
                part = s?.parts.first { $0.name.hasPrefix("Chorus") }?.name ?? s?.parts.first?.name
            }
        }
        .onChange(of: t?.previewPath) { _, _ in loadPlayer() }
        .onDisappear { player?.pause() }
    }

    private func loadPlayer() {
        guard hasPreview, let p = t?.previewPath else { player = nil; return }
        let pl = AVPlayer(url: URL(fileURLWithPath: p))
        player = pl   // starts paused: press play to watch
    }

    private var videoBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.black)
            if let player, hasPreview {
                PlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 12) {
                    if let t { TemplateThumb(t: t, width: 90) }
                    Text("Примера пока нет").font(.system(size: 14)).foregroundStyle(Color(hex: "#c4c6cc"))
                    Text("Выбери песню справа и нажми «Создать пример». Готовый ролик появится здесь.")
                        .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(width: 220)
                }
            }
        }
        .frame(width: 330, height: 587)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let t {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Что это")
                    Text(t.subtitle).font(.system(size: 13))
                    if let skill = t.skill, !skill.isEmpty {
                        Text("Делается скиллом \(skill)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    if !t.instructions.isEmpty {
                        Text(t.instructions).font(.system(size: 12)).foregroundStyle(Color(hex: "#c4c6cc")).lineLimit(8)
                    }
                    ForEach(t.facts ?? []) { f in
                        (Text(f.k + ": ").foregroundStyle(Theme.muted) + Text(f.v)).font(.system(size: 12))
                    }
                }
                if hasPreview, let p = t.previewPath {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Пример")
                        Text(URL(fileURLWithPath: p).lastPathComponent).font(.system(size: 11, design: .monospaced)).lineLimit(2)
                        HStack {
                            Button("Показать в Finder") { Finder.reveal(p) }
                            Button("Выбрать другой файл…") {
                                if let f = Finder.pickFiles().first { store.setPreview(templateId: t.id, file: f) }
                            }
                        }
                    }
                }
            }
            if let t {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Изменить шаблон", hint: store.skillExists(t.skill) ? "правка запишется в скилл \(t.skill ?? "")" : "у шаблона нет скилла")
                    StyledEditor(text: $change, placeholder: "Например: титры крупнее и жёлтым, переходы через вспышку, ролик не длиннее 20 секунд", minHeight: 56)
                    HStack {
                        Button("Записать в скилл") {
                            store.enqueueSkillEdit(templateId: t.id, change: change.trimmingCharacters(in: .whitespacesAndNewlines))
                            change = ""
                        }
                        .disabled(change.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.skillExists(t.skill))
                        if let e = editJob {
                            Text(e.status == .done ? "✓ \(e.note)" : e.status == .failed ? "✕ \(e.note)" : "Claude правит скилл…")
                                .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(hasPreview ? "Сделать новый пример" : "Создать пример")
                HStack {
                    Picker("", selection: $songId) {
                        ForEach(store.songs.filter { !$0.parts.isEmpty }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .onChange(of: songId) { _, new in
                        let s = store.song(new)
                        part = s?.parts.first { $0.name.hasPrefix("Chorus") }?.name ?? s?.parts.first?.name
                    }
                    Picker("", selection: $part) {
                        ForEach(store.song(songId)?.parts ?? []) { Text($0.name).tag(Optional($0.name)) }
                    }
                    .labelsHidden()
                }
                if let job = exampleJob {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.status == .waiting ? "Пример в очереди" : "Claude делает пример").font(.system(size: 12, weight: .semibold))
                            Text(job.note).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                        Spacer()
                        Button("Очередь") { player?.pause(); dismiss(); nav.screen = .queue; nav.selectedJob = job.id }.buttonStyle(.link)
                    }
                    .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                }
                Button(action: makeExample) {
                    Text("Создать пример").font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .foregroundStyle(Color(hex: "#1b1c21"))
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(part == nil || exampleJob != nil)
                Text("Ролик сделается как обычное задание и станет примером этого шаблона.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func makeExample() {
        guard let song = store.song(songId), let part else { return }
        _ = store.enqueueReels(song: song, picks: [(part, templateId)], variants: 1,
                               moods: song.moods, colors: song.colors, wishes: "",
                               previewFor: templateId)
    }
}
