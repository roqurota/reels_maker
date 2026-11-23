import SwiftUI
import AppKit

enum Screen: String, Hashable, CaseIterable {
    case newTask, queue, journal, publish, songs, templates
    var title: String {
        switch self {
        case .newTask: "Новое задание"
        case .queue: "Очередь"
        case .journal: "Журнал роликов"
        case .publish: "Публикация"
        case .songs: "Песни"
        case .templates: "Шаблоны"
        }
    }
    var icon: String {
        switch self {
        case .newTask: "plus.square"
        case .queue: "list.bullet"
        case .journal: "tablecells"
        case .publish: "paperplane"
        case .songs: "music.note"
        case .templates: "rectangle.3.group"
        }
    }
}

@MainActor
@Observable
final class Nav {
    var screen: Screen = .newTask
    var editingSong: Song?
    var showNewTemplate = false
    var previewTemplate: ReelTemplate?
    var showSkillTemplate = false
    var selectedJob: UUID?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Store.current?.runner.stopAll() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ReelsStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = Store()
    @State private var nav = Nav()

    var body: some Scene {
        WindowGroup("Reels Studio") {
            ContentView()
                .environment(store)
                .environment(nav)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .defaultSize(width: 1320, height: 880)
        Settings {
            SettingsView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            List(selection: $nav.screen) {
                ForEach(Screen.allCases, id: \.self) { s in
                    Label(s.title, systemImage: s.icon)
                        .badge(s == .queue ? store.jobs.filter { $0.status == .waiting || $0.status == .running }.count : 0)
                        .tag(s)
                }
            }
            .navigationSplitViewColumnWidth(210)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            VStack(spacing: 0) {
                if let err = store.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
                        Text(err).font(.callout)
                        Spacer()
                        Button("Обновить") { store.load(); store.runner.kick() }
                    }
                    .padding(10).background(Color(hex: "#2a2117"))
                }
                switch nav.screen {
                case .newTask: NewTaskView()
                case .queue: QueueView()
                case .journal: JournalView()
                case .songs: SongsView()
                case .templates: TemplatesView()
                case .publish: PublishView()
                }
            }
            .background(Theme.bg)
        }
        .sheet(item: $nav.editingSong) { song in
            SongEditorView(song: song)
        }
        .sheet(isPresented: $nav.showNewTemplate) {
            NewTemplateView()
        }
        .sheet(isPresented: $nav.showSkillTemplate) {
            SkillTemplateView()
        }
        .sheet(item: $nav.previewTemplate) { t in
            TemplatePreviewView(templateId: t.id)
        }
    }
}

struct SidebarFooter: View {
    @Environment(Store.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.bottom, 6)
            Text("Папка проекта").font(.caption).foregroundStyle(Theme.muted)
            Text(URL(fileURLWithPath: store.reelsRoot).lastPathComponent).font(.caption)
            HStack(spacing: 6) {
                Circle().fill(store.rootAvailable ? Color(hex: "#5fbf7f") : Color(hex: "#c8323c")).frame(width: 7, height: 7)
                Text(store.rootAvailable ? "Диск подключён" : "Диск не найден").font(.caption).foregroundStyle(Theme.muted)
            }
            SettingsLink { Label("Настройки", systemImage: "gearshape") }
                .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.muted).padding(.top, 4)
        }
        .padding(12)
    }
}
