import Foundation
import SwiftUI

// MARK: - Songs

struct SongPart: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var wav: String?
    var srt: String?
    var duration: Double?
    var firstLine: String?

    var durationText: String {
        guard let d = duration else { return "" }
        return "\(Int(d.rounded())) с"
    }
}

struct Song: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var release: String
    var folder: String
    var description: String
    var moods: [String]
    var colors: [String]          // ids from Palette or "#rrggbb"
    var links: String
    var parts: [SongPart]         // refreshed from <folder>/Titles on every load
    var mediaFolders: [String]?   // footage to use; empty = Claude picks from the band's media
    var usePexels: Bool?          // also mix in Pexels clips (default on)

    var media: [String] { mediaFolders ?? [] }
    var pexels: Bool { usePexels ?? true }

    static func newEmpty() -> Song {
        Song(id: UUID().uuidString, name: "", release: "Сингл", folder: "", description: "",
             moods: [], colors: [], links: "", parts: [])
    }
}

// MARK: - Colors

struct ColorTag: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: String
}

enum Palette {
    static let all: [ColorTag] = [
        ColorTag(id: "red", name: "красный", hex: "#c8323c"),
        ColorTag(id: "amber", name: "оранжевый", hex: "#d9822b"),
        ColorTag(id: "yellow", name: "жёлтый", hex: "#d8b23a"),
        ColorTag(id: "teal", name: "бирюзовый", hex: "#4f8a8b"),
        ColorTag(id: "blue", name: "синий", hex: "#2f5fbf"),
        ColorTag(id: "violet", name: "фиолетовый", hex: "#7d55b0"),
        ColorTag(id: "pink", name: "розовый", hex: "#c95a8a"),
        ColorTag(id: "warm", name: "тёплая плёнка", hex: "#b08a5a"),
        ColorTag(id: "mono", name: "чёрно-белый", hex: "#9a9a9a"),
    ]

    static func tag(_ id: String) -> ColorTag {
        if let t = all.first(where: { $0.id == id }) { return t }
        return ColorTag(id: id, name: id, hex: id.hasPrefix("#") ? id : "#888888")
    }

    static let moods = ["погоня", "тревога", "ночь", "загадка", "меланхолия", "драйв",
                        "нежность", "надежда", "злость", "свобода"]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02x%02x%02x", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }
}

// MARK: - Templates

struct Fact: Codable, Hashable, Identifiable {
    var id: String { k }
    var k: String
    var v: String
}

struct ReelTemplate: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var subtitle: String
    var short: String             // used in file names
    var skill: String?            // e.g. "reels-letterbox"
    var instructions: String      // extra style description for Claude
    var reference: String?
    var facts: [Fact]?
    var builtIn: Bool
    // tiny preview
    var stripHeight: Double       // 0...1 of preview height
    var stripHex: String
    var word: String
    var wordHex: String
    var previewPath: String? = nil  // example reel shown in the template popup
    var archived: Bool? = nil       // hidden from new tasks, kept in the Templates archive

    /// Reels already made in these styles; used until a template gets its own example.
    static let knownExamples: [String: String] = {
        let r = "/Volumes/The Last Roman/The Last Roman/Media/Reels/2026/Claude/"
        return ["letterbox": r + "13 Nov/13 Nov Marlo Chorus 1 1080x1920.mp4",
                "sketch": r + "15 Nov v2/15 Nov Thousand Years Chorus Sketch 1080x1920.mp4",
                "winter": r + "18 Nov/18 Nov Thousand Years Chorus Winter 1080x1920.mp4"]
    }()

    static let builtIns: [ReelTemplate] = [
        ReelTemplate(id: "letterbox", name: "Кинополоса", subtitle: "Стиль 1. Полоса видео, плёнка, строчные титры", short: "Kinopolosa",
                     skill: "reels-letterbox", instructions: "", reference: nil, facts: nil, builtIn: true,
                     stripHeight: 0.28, stripHex: "#6b5a4a", word: "run", wordHex: "#ffffff"),
        ReelTemplate(id: "sketch", name: "Скетч", subtitle: "Стиль 2. Концерт, меловые контуры, красные слова", short: "Sketch",
                     skill: "reels-sketch", instructions: "", reference: nil, facts: nil, builtIn: true,
                     stripHeight: 1, stripHex: "#3a3a3e", word: "RUN", wordHex: "#e0444c"),
        ReelTemplate(id: "winter", name: "Зима", subtitle: "Стиль 3. Pexels, снег и туман, холодный монохром", short: "Winter",
                     skill: "reels-winter", instructions: "", reference: nil, facts: nil, builtIn: true,
                     stripHeight: 0.4, stripHex: "#6f8586", word: "run", wordHex: "#2b2d30"),
        ReelTemplate(id: "fx", name: "FX-погоня", subtitle: "Маска человека, двойная экспозиция, склейки по словам", short: "FX",
                     skill: "reels-fx", instructions: "", reference: nil, facts: nil, builtIn: true,
                     stripHeight: 1, stripHex: "#5a1a1f", word: "RUN", wordHex: "#ffffff"),
        ReelTemplate(id: "basic", name: "Простой монтаж", subtitle: "Нарезка под слова, переходы, титры-шаблоны", short: "Basic",
                     skill: "davinci-reels", instructions: "", reference: nil, facts: nil, builtIn: true,
                     stripHeight: 1, stripHex: "#3c4250", word: "Run", wordHex: "#ffffff"),
    ]
}

// MARK: - Jobs

enum JobKind: String, Codable { case reel, analyze, skillEdit, publish }
enum JobStatus: String, Codable { case waiting, running, done, failed, cancelled }

struct Job: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: JobKind = .reel
    var title: String
    var songId: String?
    var songName: String?
    var part: String?
    var templateId: String?
    var templateName: String?
    var variant: Int = 1
    var moods: [String] = []
    var colors: [String] = []
    var wishes: String = ""
    var prompt: String = ""
    var workDir: String            // job folder (task.json, log, result.json)
    var outputDir: String          // where the reel goes
    var fileName: String?
    var status: JobStatus = .waiting
    var note: String = ""
    var log: [String] = []
    var sessionId: UUID = UUID()
    var sessionStarted: Bool = false
    var createdAt: Date = Date()
    var startedAt: Date?
    var finishedAt: Date?
    var resultFiles: [String] = []
    var pendingRevision: String?   // comment for a follow-up run in the same Claude session
    var previewFor: String?        // template id: the result becomes that template's example
    var pid: Int32?                // claude process, to stop it even after an app restart
    var mediaFolders: [String]?
    var usePexels: Bool?
    var revisions: [String]?       // comments sent through «Доработать»
    var entryId: UUID?             // journal entry a publish job posts
    var dryRun: Bool?              // publish: prepare everything but don't press Publish
}

// MARK: - Journal

struct ReelEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var file: String
    var song: String
    var part: String
    var template: String
    var published: Bool = false
    var platforms: String = ""
    var tiktokURL: String? = nil
}

/// What the user set up for one reel on the Publish page (kept between app runs).
struct PublishDraft: Codable, Hashable {
    var caption: String = ""
    var variants: [String] = []
    var privacy: String? = nil            // "Все" / "Друзья" / "Только я"; no default, the user picks
    var allowComments = true
    var allowDuet = true
    var allowStitch = true
    var aiLabel = false
    var soundStart: String = ""           // where the official track should start, m:ss (empty: Claude finds it)
    var soundMode: String? = nil          // "link": track at volume 0 just for the song link (default); "track": track audible
    var linkOnly: Bool { (soundMode ?? "link") == "link" }
    var coverSec: String = ""             // cover frame, seconds (empty: TikTok default)
}

enum TikTok {
    static let privacyOptions = ["Все", "Друзья", "Только я"]
    static let captionLimit = 2200
}
