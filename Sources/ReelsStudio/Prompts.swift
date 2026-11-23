import Foundation

/// Texts sent to Claude Code. Kept in one place so they are easy to tune.
@MainActor
enum Prompts {
    static func reel(job: Job, song: Song, template t: ReelTemplate, store: Store) -> String {
        let part = song.parts.first { $0.name == job.part }
        let colors = job.colors.map { let c = Palette.tag($0); return "\(c.name) (\(c.hex))" }.joined(separator: ", ")
        var lines: [String] = []
        lines.append("Задание из Reels Studio. Сделай вертикальный рилс 9:16 группы The Last Roman.")
        lines.append("")
        lines.append("Песня: \(song.name) (\(song.release)). Папка песни: \(song.folder)")
        lines.append("Часть: \(job.part ?? "")")
        if let wav = part?.wav { lines.append("Аудио части: \(wav)") }
        if let srt = part?.srt { lines.append("Титры по словам: \(srt)") }
        if !song.description.isEmpty { lines.append("Описание песни: \(song.description)") }
        if !job.moods.isEmpty { lines.append("Настроение: \(job.moods.joined(separator: ", "))") }
        if !colors.isEmpty { lines.append("Цвета, которые передают настроение: \(colors)") }
        if !song.links.isEmpty { lines.append("Ссылки по песне: \(song.links)") }
        lines.append("")
        lines.append("Шаблон: \(t.name). \(t.subtitle)")
        if let skill = t.skill, !skill.isEmpty {
            lines.append("Шаблон = скилл \(skill). Сначала загрузи его и делай строго по его рецепту: формат, грейд, титры, шрифт, переходы, темп склеек, звук, проверка.")
            lines.append("Ничего не придумывай сверх скилла. Свободно выбираешь только кадры и их порядок. Если в скилле чего-то не хватает, возьми самое близкое из его примеров и коротко напиши об этом в notes.")
            lines.append("Пожелания ниже важнее скилла, но только для этого ролика.")
        }
        if !t.instructions.isEmpty { lines.append("Описание стиля: \(t.instructions)") }
        if let facts = t.facts, !facts.isEmpty {
            lines.append("Разбор стиля:")
            for f in facts { lines.append("- \(f.k): \(f.v)") }
        }
        if let ref = t.reference, !ref.isEmpty { lines.append("Референс: \(ref)") }
        if !job.wishes.isEmpty { lines.append("Пожелания: \(job.wishes)") }
        lines.append("")
        let media = job.mediaFolders ?? []
        if media.isEmpty {
            lines.append("Медиа: папки не заданы, выбери подходящие видео группы сам (Media/Video на диске The Last Roman).")
        } else {
            lines.append("Медиа: бери видео и фото группы только из этих папок (и их подпапок), другие не используй:")
            for f in media { lines.append("- \(f)") }
        }
        let pexelsSong = store.pexelsDir.appendingPathComponent(song.name).path
        if job.usePexels ?? true {
            lines.append("Pexels: да. Дополнительно подбери футажи с Pexels по смыслу текста и настроению и смонтируй вперемешку с основным материалом (основной материал главный, Pexels примерно треть планов).")
            lines.append("Все скачанные с Pexels файлы сохраняй только в \(pexelsSong) с понятными именами. Сначала посмотри, что там уже лежит, и используй подходящее повторно. Старые Pexels-клипы из папки песни тоже можно брать.")
        } else {
            lines.append("Pexels: нет. Ничего не скачивай и не бери Pexels-клипы, только материал группы.")
        }
        if job.variant > 1 { lines.append("Это вариант \(job.variant): сделай его заметно отличающимся от варианта 1 (другие кадры, другой порядок).") }
        lines.append("")
        lines.append("Готовый ролик сохрани ровно сюда: \(job.outputDir)/\(job.fileName ?? "reel.mp4")")
        lines.append("Рабочие и временные файлы держи в текущей папке (\(job.workDir)).")
        lines.append("Работаешь в фоне, вопросы задать некому: если скилл просит что-то уточнить, например папки с видео, выбери сам подходящее и коротко напиши, что выбрал.")
        lines.append("Перед финалом проверь результат, как требует скилл.")
        lines.append("В конце запиши в текущую папку файл result.json: {\"files\": [\"<абсолютный путь к готовому mp4>\"], \"notes\": \"2-3 предложения: что сделано и что выбрал\"}.")
        return lines.joined(separator: "\n")
    }

    static func skillEdit(template t: ReelTemplate, skill: String, change: String, workDir: String, store: Store) -> String {
        let path = Store.skillsHome.appendingPathComponent(skill).appendingPathComponent("SKILL.md").path
        return """
        Задание из Reels Studio: обновить скилл шаблона «\(t.name)».
        Скилл: \(skill) (\(path)).

        Что поменять:
        \(change)

        Это постоянное правило шаблона: впиши его в рецепт скилла так, чтобы каждый следующий рилс в этом шаблоне делался так автоматически, без напоминаний.
        Перед правкой сохрани копию \(path) как SKILL.md.bak рядом.
        Меняй только этот скилл. Общие скрипты других скиллов (например davinci-reels) не трогай: если нужен новый параметр или шаг, добавь его в этот скилл или его собственный скрипт.
        Не переписывай то, что к правке не относится. Пиши по-русски, коротко, без длинных тире.
        Работаешь в фоне, вопросов не задавай. В конце запиши в \(workDir)/result.json: {"notes": "что именно изменено в скилле, 2-3 предложения"}.
        """
    }

    static func analyze(reference: String, about: String, files: [String], workDir: String, store: Store) -> String {
        var lines: [String] = []
        lines.append("Задание из Reels Studio: разобрать референс и сделать из него шаблон для рилсов группы The Last Roman.")
        if !reference.isEmpty { lines.append("Ссылки на референс: \(reference)") }
        if !files.isEmpty { lines.append("Файлы референса: \(files.joined(separator: ", "))") }
        if !about.isEmpty { lines.append("Что нравится автору: \(about)") }
        lines.append("")
        lines.append("Попробуй открыть ссылку и посмотреть ролик (кадры, ffmpeg для файлов). Если ссылка недоступна, опирайся на файлы и описание и честно отметь это в notes.")
        lines.append("Готовые стили для сравнения: reels-letterbox (Кинополоса), reels-sketch (Скетч), reels-winter (Зима), reels-fx (FX-погоня), davinci-reels (простой монтаж).")
        lines.append("Работаешь в фоне, вопросов не задавай.")
        lines.append("")
        lines.append("Главное: шаблон должен стать скиллом, чтобы каждый следующий рилс в этом стиле делался по одному рецепту, а не придумывался заново.")
        lines.append("1. Придумай имя скилла: reels-<коротко латиницей через дефис>, которого ещё нет в ~/.claude/skills.")
        lines.append("2. Возьми за основу самый близкий готовый скилл из списка выше. Создай ~/.claude/skills/<имя>/SKILL.md (frontmatter name и description по-русски: что за стиль и когда его использовать) с полным пошаговым рецептом: подготовка, выбор кадров, кадрирование, грейд, титры (шрифт, размер, цвет, позиция, анимация), переходы, темп склеек, звук, рендер, проверка.")
        lines.append("Скрипты базового скилла используй по их путям, не копируй и не меняй чужие скиллы. Новые скрипты, если нужны, клади в папку нового скилла.")
        lines.append("3. Запиши в \(workDir)/template.json объект:")
        lines.append("{\"name\": \"короткое название стиля\", \"subtitle\": \"одна строка: суть стиля\", \"skill\": \"имя созданного скилла\", \"base\": \"скилл-основа\",\"instructions\": \"подробное описание стиля для монтажа: кадрирование, цвет, титры, шрифт, темп склеек, эффекты, звук\", \"facts\": [{\"k\": \"Формат\", \"v\": \"...\"}, {\"k\": \"Цвет и грейд\", \"v\": \"...\"}, {\"k\": \"Титры\", \"v\": \"...\"}, {\"k\": \"Темп склеек\", \"v\": \"...\"}, {\"k\": \"Эффекты\", \"v\": \"...\"}, {\"k\": \"Чем делать\", \"v\": \"...\"}], \"stripHex\": \"#rrggbb основной цвет\", \"notes\": \"что удалось посмотреть\"}")
        lines.append("Пиши по-русски, коротко, без длинных тире.")
        return lines.joined(separator: "\n")
    }
}
