import SwiftUI
import AppKit

enum Theme {
    static let bg = Color(hex: "#141519")
    static let panel = Color(hex: "#1b1c21")
    static let card = Color(hex: "#1f2026")
    static let border = Color(hex: "#2f3138")
    static let accent = Color(hex: "#e8833a")
    static let accentSoft = Color(hex: "#2b2219")
    static let muted = Color(hex: "#9a9ca3")
    static let text = Color(hex: "#e8e8ea")
    static let good = Color(hex: "#5fbf7f")
}

struct SectionLabel: View {
    let text: String
    var hint: String? = nil
    init(_ text: String, hint: String? = nil) { self.text = text; self.hint = hint }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.6).foregroundStyle(Theme.muted)
            if let hint { Text(hint).font(.caption).foregroundStyle(Theme.muted) }
        }
    }
}

struct Chip: View {
    let label: String
    let on: Bool
    var strikeWhenOff = false
    var square = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .strikethrough(strikeWhenOff && !on)
                .padding(.horizontal, 12).frame(height: 28)
                .foregroundStyle(on ? Color(hex: "#1b1c21") : Color(hex: "#c4c6cc"))
                .background(on ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: square ? 7 : 14))
                .overlay(RoundedRectangle(cornerRadius: square ? 7 : 14).stroke(on ? Theme.accent : Color(hex: "#34373e")))
        }
        .buttonStyle(.plain)
    }
}

struct ColorChip: View {
    let tag: ColorTag
    let on: Bool
    var showName = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: tag.hex)).frame(width: 14, height: 14)
                if showName { Text(tag.name).font(.system(size: 12)) }
            }
            .padding(.leading, 8).padding(.trailing, showName ? 12 : 8).frame(height: 30)
            .background(on ? Theme.accentSoft : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(on ? Theme.accent : Color(hex: "#34373e")))
            .opacity(on || showName ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .help(tag.name)
    }
}

/// Small 9:16 preview of a template.
struct TemplateThumb: View {
    let t: ReelTemplate
    var width: CGFloat = 32
    var body: some View {
        let h = width * 16 / 9
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4).fill(.black)
            Rectangle().fill(Color(hex: t.stripHex))
                .frame(width: width, height: h * t.stripHeight)
                .frame(maxHeight: .infinity)
            Text(t.word).font(.system(size: width / 6, weight: .bold)).foregroundStyle(Color(hex: t.wordHex))
                .padding(.top, h * 0.22)
        }
        .frame(width: width, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    var highlight = false
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlight ? Color(hex: "#211d19") : Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(highlight ? Color(hex: "#6a4a2e") : Color(hex: "#2a2c33")))
    }
}

struct StyledEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 70
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text(placeholder).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
    }
}

enum Finder {
    static func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
    static func open(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }

    @MainActor
    static func pickFolder(start: String) -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.directoryURL = URL(fileURLWithPath: start)
        return p.runModal() == .OK ? p.url?.path : nil
    }

    @MainActor
    static func pickFiles() -> [String] {
        let p = NSOpenPanel()
        p.canChooseDirectories = false; p.canChooseFiles = true; p.allowsMultipleSelection = true
        p.allowedContentTypes = [.movie, .image, .video]
        return p.runModal() == .OK ? p.urls.map(\.path) : []
    }
}

func pluralReels(_ n: Int) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return "\(n) ролик" }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return "\(n) ролика" }
    return "\(n) роликов"
}

/// Footage folders for a reel plus the "also use Pexels" switch.
struct MediaPicker: View {
    @Binding var folders: [String]
    @Binding var usePexels: Bool
    var hint: String? = nil
    var startFolder: String = "/Volumes/The Last Roman/The Last Roman/Media/Video"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Медиа для рилса", hint: folders.isEmpty ? "папки не выбраны: Claude подберёт сам" : nil)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(folders, id: \.self) { f in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(URL(fileURLWithPath: f).lastPathComponent).font(.system(size: 13, weight: .medium))
                            Text(f).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Button { Finder.open(f) } label: { Image(systemName: "arrow.up.forward.square") }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Открыть в Finder")
                        Button { folders.removeAll { $0 == f } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Убрать папку")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                }
                Button {
                    if let p = Finder.pickFolder(start: folders.last ?? startFolder), !folders.contains(p) { folders.append(p) }
                } label: {
                    Text("+ Добавить папку с видео").font(.system(size: 12)).frame(maxWidth: .infinity).frame(height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color(hex: "#4a4d55")))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Toggle(isOn: $usePexels) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Добавлять футажи с Pexels").font(.system(size: 13))
                    Text(usePexels ? "Claude найдёт подходящие по смыслу и смешает с основным материалом. Скачанное хранится в _studio/pexels."
                                   : "Только материал из папок выше.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .toggleStyle(.switch)
            if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(Theme.muted) }
        }
    }
}
