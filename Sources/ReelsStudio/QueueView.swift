import SwiftUI

struct QueueView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    @State private var revision = ""

    private var selected: Job? {
        store.jobs.first { $0.id == nav.selectedJob }
            ?? store.jobs.first { $0.status == .running }
            ?? store.jobs.last
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Очередь").font(.system(size: 18, weight: .semibold))
                Text(summary).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if store.jobs.contains(where: { $0.status == .failed }) {
                    Button("Повторить неудачные") { store.retryFailed() }
                }
                Button(store.runner.paused ? "Продолжить очередь" : "Пауза очереди") {
                    store.runner.paused.toggle()
                    if !store.runner.paused { store.lastError = nil; store.runner.kick() }
                }
                Button("Убрать готовые") { store.clearFinished() }
            }
            .padding(.horizontal, 24).frame(height: 60)
            Divider()
            HStack(spacing: 0) {
                list
                Divider()
                detail.frame(width: 440)
            }
        }
    }

    private var summary: String {
        let r = store.jobs.filter { $0.status == .running }.count
        let w = store.jobs.filter { $0.status == .waiting }.count
        let d = store.jobs.filter { $0.status == .done }.count
        return "\(r) в работе · \(w) ждут · \(d) готово"
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if store.jobs.isEmpty {
                    Text("Заданий нет. Создай их на экране «Новое задание».").foregroundStyle(Theme.muted).padding(.top, 40)
                }
                group("В работе", store.jobs.filter { $0.status == .running })
                group("Ждут", store.jobs.filter { $0.status == .waiting })
                group("Готово", store.jobs.filter { $0.status == .done }.reversed())
                group("Не получилось", store.jobs.filter { $0.status == .failed || $0.status == .cancelled }.reversed())
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ jobs: [Job]) -> some View {
        if !jobs.isEmpty {
            SectionLabel(title).padding(.top, 8)
            ForEach(jobs) { j in row(j) }
        }
    }

    private func row(_ j: Job) -> some View {
        let isSel = j.id == selected?.id
        return Button { nav.selectedJob = j.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    statusIcon(j.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(j.title + (j.variant > 1 ? " · v\(j.variant)" : "")).font(.system(size: 13, weight: .semibold))
                        if !j.note.isEmpty {
                            Text(j.note).font(.system(size: 12)).foregroundStyle(Color(hex: "#b4b6bc")).lineLimit(1)
                        }
                    }
                    Spacer()
                    if let s = j.startedAt, j.status == .running {
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text("идёт \(Int(Date().timeIntervalSince(s) / 60)) мин").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if j.status == .running { ProgressView().progressViewStyle(.linear).tint(Theme.accent) }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSel ? Theme.accent : Color(hex: "#2a2c33")))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if j.status == .waiting || j.status == .running { Button("Отменить") { store.cancel(j.id) } }
            if j.status == .failed || j.status == .cancelled { Button("Повторить") { store.retry(j.id) } }
            Button("Открыть папку задания") { Finder.reveal(j.workDir) }
            Button("Удалить из списка", role: .destructive) { store.remove(j.id) }
        }
    }

    private func statusIcon(_ s: JobStatus) -> some View {
        switch s {
        case .running: Image(systemName: "circle.dotted").foregroundStyle(Theme.accent)
        case .waiting: Image(systemName: "clock").foregroundStyle(Theme.muted)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(hex: "#e0444c"))
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let j = selected {
            VStack(alignment: .leading, spacing: 14) {
                Text(j.title).font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 5) {
                    if j.kind == .reel {
                        info("Шаблон", j.templateName ?? "")
                        if !j.moods.isEmpty { info("Настроение", j.moods.joined(separator: ", ")) }
                        if !j.colors.isEmpty {
                            HStack(spacing: 6) {
                                Text("Цвета:").foregroundStyle(Theme.muted)
                                ForEach(j.colors, id: \.self) { c in Circle().fill(Color(hex: Palette.tag(c).hex)).frame(width: 11, height: 11) }
                            }.font(.system(size: 12))
                        }
                        if !j.wishes.isEmpty { info("Пожелания", j.wishes) }
                        info("Файл", j.fileName ?? "")
                    }
                }
                HStack {
                    if j.status == .done, let f = j.resultFiles.first {
                        Button("Открыть ролик") { Finder.open(f) }
                        Button("Показать в Finder") { Finder.reveal(f) }
                    } else {
                        Button("Папка задания") { Finder.reveal(j.workDir) }
                    }
                    Spacer()
                    if j.status == .waiting || j.status == .running { Button("Отменить") { store.cancel(j.id) } }
                    if j.status == .failed || j.status == .cancelled { Button("Повторить") { store.retry(j.id) } }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(j.log.suffix(300).enumerated()), id: \.offset) { i, line in
                                Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "#a9abb2"))
                                    .textSelection(.enabled).id(i)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(hex: "#0f1013"), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: j.log.count) { _, _ in proxy.scrollTo(min(j.log.count, 300) - 1, anchor: .bottom) }
                }
                if j.kind == .reel && j.status == .done, let revs = j.revisions, !revs.isEmpty,
                   store.skillExists(store.template(j.templateId)?.skill) {
                    Button {
                        let text = revs.map { "- " + $0 }.joined(separator: "\n")
                        store.enqueueSkillEdit(templateId: j.templateId ?? "",
                                               change: "Эти правки к ролику «\(j.title)» понравились, сделай их постоянной частью шаблона:\n" + text)
                    } label: {
                        Label("Запомнить правки в шаблоне «\(j.templateName ?? "")»", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12))
                    }
                    .help("Правки к этому ролику станут правилом скилла, и следующие рилсы в этом шаблоне будут делаться так же")
                }
                if j.kind == .reel && (j.status == .done || j.status == .failed) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Доработать")
                        StyledEditor(text: $revision, placeholder: "Например: титры крупнее, меньше зерна", minHeight: 50)
                        Button {
                            store.revise(j.id, comment: revision.trimmingCharacters(in: .whitespacesAndNewlines))
                            revision = ""
                        } label: {
                            Text("Отправить правку").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 34)
                                .foregroundStyle(Color(hex: "#1b1c21")).background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(hex: "#17181c"))
        } else {
            Text("Выбери задание").foregroundStyle(Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: "#17181c"))
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        (Text(k + ": ").foregroundStyle(Theme.muted) + Text(v)).font(.system(size: 12))
    }
}
