// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The island terminal in words. English only, like everything else SasNotch
/// added on top of the upstream app.
enum NotchTerminalText {
    static let title = "Terminal"
    static let hubDescription = "Run quick commands from the island in your login shell. "
        + "Programs that take over the screen or ask for input still need Terminal."
    static let settingsCaption = "Commands run as you, in your login shell, with nothing to read from: "
        + "full-screen programs such as vim or top, and commands that ask a question, need Terminal. "
        + "sudo, su and doas are never run. Output and history last until SasNotch quits."
    static let summary = "A prompt for quick commands in your login shell."
    static let placeholder = "Command"
    static let emptyHint = "Type a command and press Return. ↑ and ↓ bring back earlier ones."
    static let stop = "Stop"
    static let clear = "Clear"
    static let openInTerminal = "Open in Terminal"
    static let stopped = "Stopped"
    static let elevationBlocked = "SasNotch doesn't run sudo, su or doas. Use Terminal for commands that need a password."
    static let noTerminal = "Terminal couldn't be opened."
    static let noPreviousDirectory = "cd: no previous directory"
    static let tooManyArguments = "cd: too many arguments"
    static func exitStatus(_ code: Int32) -> String { "Exit status \(code)" }
    static func endedBy(_ signal: String) -> String { "Ended by \(signal)" }
    static func noSuchDirectory(_ path: String) -> String { "cd: no such file or directory: \(path)" }
    static func notDirectory(_ path: String) -> String { "cd: not a directory: \(path)" }
    static func permissionDenied(_ path: String) -> String { "cd: permission denied: \(path)" }
    static func cannotExpand(_ argument: String) -> String {
        "cd: can't expand \(argument) here. Type the folder's path instead."
    }
    static func launchFailed(_ reason: String) -> String { "Couldn't start your shell: \(reason)" }
    static func folderGone(_ path: String) -> String { "\(path) is gone, so this runs in your home folder." }
}

enum NotchTerminalSupport {
    /// The page shows, and so may run something, only while the island is on,
    /// the feature installed and its page not hidden.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && NotchSupport.modules(in: defaults).contains(.terminal)
    }

    /// The mark the login shell itself puts before a command.
    static func promptSymbol(shell: String) -> String {
        (shell as NSString).lastPathComponent == "zsh" ? "%" : "$"
    }
}

/// The keys the prompt answers itself. Everything else, Escape included,
/// goes where it always goes.
enum NotchTerminalKey: Equatable {
    case older, newer, submit, interrupt, clear

    init?(keyCode: UInt16, characters: String, command: Bool, control: Bool, option: Bool, shift: Bool) {
        let plain = !command && !control && !option && !shift
        switch keyCode {
        case 126 where plain: self = .older
        case 125 where plain: self = .newer
        case 36 where plain, 76 where plain: self = .submit
        default:
            // By character, so the shortcuts follow the keyboard layout.
            guard control, !command, !option, !shift else { return nil }
            switch characters.lowercased() {
            case "c": self = .interrupt
            case "l": self = .clear
            default: return nil
            }
        }
    }
}

// MARK: - Scrollback and history

enum NotchTerminalLineKind: Equatable {
    /// A command as typed, after the folder it ran in.
    case command
    case output
    /// What a command wrote to stderr, tinted.
    case error
    /// What the island says itself: a refused sudo, an exit status, a stop.
    case notice
}

struct NotchTerminalLine: Identifiable, Equatable {
    let id: Int
    let kind: NotchTerminalLineKind
    let text: String
}

/// What the page shows, oldest first, holding at most `limit` lines.
struct NotchTerminalScrollback: Equatable {
    static let defaultLimit = 2000
    let limit: Int
    private(set) var lines: [NotchTerminalLine] = []
    /// The id the next line gets. It keeps counting through a clear and past
    /// lines a burst pushed out, so a view never takes a new line for one it
    /// already showed.
    private(set) var nextID = 0

    init(limit: Int = defaultLimit) {
        self.limit = max(1, limit)
    }

    var isEmpty: Bool { lines.isEmpty }

    mutating func append(_ kind: NotchTerminalLineKind, _ text: String) {
        append([(kind: kind, text: text)])
    }

    mutating func append(_ batch: [(kind: NotchTerminalLineKind, text: String)]) {
        guard !batch.isEmpty else { return }
        // A burst longer than the whole scrollback keeps only its end.
        let kept = batch.suffix(limit)
        nextID += batch.count - kept.count
        for entry in kept {
            lines.append(NotchTerminalLine(id: nextID, kind: entry.kind, text: entry.text))
            nextID += 1
        }
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
    }

    mutating func clear() {
        lines.removeAll()
    }
}

/// Commands run since launch, for Up and Down at the prompt. Kept in memory
/// only, like the scrollback.
struct NotchTerminalHistory: Equatable {
    static let limit = 200
    private(set) var entries: [String] = []
    /// The entry Up and Down have reached, nil at the prompt.
    private var position: Int?
    /// What was typed before Up, which Down brings back.
    private var draft = ""

    var isBrowsing: Bool { position != nil }

    /// A blank line and a repeat of the last command add nothing.
    mutating func record(_ command: String) {
        position = nil
        draft = ""
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entries.last != trimmed else { return }
        entries.append(trimmed)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    /// The command before the one shown, or nil at the oldest.
    mutating func older(than current: String) -> String? {
        guard !entries.isEmpty else { return nil }
        guard let position else {
            draft = current
            self.position = entries.count - 1
            return entries[entries.count - 1]
        }
        guard position > 0 else { return nil }
        self.position = position - 1
        return entries[position - 1]
    }

    /// The command after the one shown, then what was being typed; nil at the prompt.
    mutating func newer() -> String? {
        guard let position else { return nil }
        if position < entries.count - 1 {
            self.position = position + 1
            return entries[position + 1]
        }
        self.position = nil
        return draft
    }

    mutating func clear() {
        entries = []
        position = nil
        draft = ""
    }
}

// MARK: - Reading a command line

struct NotchTerminalWord: Equatable {
    /// The word as typed.
    var raw = ""
    /// With its quotes and backslashes taken off and the known variables filled in.
    var value = ""
    /// It starts with an unquoted ~.
    var tilde = false
    /// It holds something only the shell can expand: another variable, a
    /// pattern, braces or a command substitution.
    var expands = false
}

enum NotchTerminalToken: Equatable {
    case word(NotchTerminalWord)
    /// ; && || | |& & ;; ( ) and a line break.
    case separator(String)
    /// < > >> and the others; the word after one names a file.
    case redirection(String)
}

/// A command line split the way the shell splits it, far enough to follow a
/// leading `cd` and to find a `sudo` anywhere a command can start. It is not
/// a shell: what it can't be sure of is left to the shell, or refused.
struct NotchTerminalLexed: Equatable {
    var tokens: [NotchTerminalToken] = []
    /// Where in the line each token ends.
    var ends: [String.Index] = []
    /// What each `$(…)` and backtick runs, to be read the same way.
    var substitutions: [String] = []
    /// False while a quote or a substitution is still open at the end.
    var complete = true
}

enum NotchTerminalShellWords {
    private static let operatorCharacters: Set<Character> = [";", "&", "|", "(", ")", "<", ">"]
    private static let doubleOperators: Set<String> = ["&&", "||", ";;", "|&", ">>", "<<", ">&", "<&", "&>", ">|", "<>"]

    static func lex(_ line: String, variables: [String: String] = [:]) -> NotchTerminalLexed {
        var result = NotchTerminalLexed()
        var word = NotchTerminalWord()
        var inWord = false
        var index = line.startIndex

        func endWord(_ end: String.Index) {
            guard inWord else { return }
            result.tokens.append(.word(word))
            result.ends.append(end)
            word = NotchTerminalWord()
            inWord = false
        }

        func add(_ token: NotchTerminalToken, _ end: String.Index) {
            result.tokens.append(token)
            result.ends.append(end)
        }

        /// A `$` at `start`: a variable, `${…}` or `$(…)`. Returns the index after it.
        func dollar(at start: String.Index) -> String.Index {
            let next = line.index(after: start)
            guard next < line.endIndex else {
                word.raw.append("$")
                word.value.append("$")
                word.expands = true
                return next
            }
            if line[next] == "(" {
                return substitution(from: start, open: next)
            }
            if line[next] == "{" {
                let close = line[next...].firstIndex(of: "}")
                let end = close.map { line.index(after: $0) } ?? line.endIndex
                let name = String(line[line.index(after: next)..<(close ?? line.endIndex)])
                word.raw.append(contentsOf: line[start..<end])
                if close == nil { result.complete = false }
                if close != nil, let value = variables[name] {
                    word.value.append(contentsOf: value)
                } else {
                    word.value.append(contentsOf: line[start..<end])
                    word.expands = true
                }
                return end
            }
            var end = next
            if "?$!#*@-".contains(line[next]) {
                // $?, $$, $! and the like: only the shell knows them.
                end = line.index(after: next)
            } else {
                while end < line.endIndex, isNameCharacter(line[end]) {
                    end = line.index(after: end)
                    // $1 is one digit; $12 is $1 then a 2.
                    if line[next].isNumber { break }
                }
            }
            guard end > next else {
                // A $ before nothing it can expand stands for itself.
                word.raw.append("$")
                word.value.append("$")
                return next
            }
            let name = String(line[next..<end])
            word.raw.append(contentsOf: line[start..<end])
            if let value = variables[name] {
                word.value.append(contentsOf: value)
            } else {
                word.value.append(contentsOf: line[start..<end])
                word.expands = true
            }
            return end
        }

        /// `$(` at `start`, its parenthesis at `open`.
        func substitution(from start: String.Index, open: String.Index) -> String.Index {
            word.expands = true
            if let close = matchingParenthesis(in: line, from: open) {
                result.substitutions.append(String(line[line.index(after: open)..<line.index(before: close)]))
                word.raw.append(contentsOf: line[start..<close])
                word.value.append(contentsOf: line[start..<close])
                return close
            }
            result.complete = false
            result.substitutions.append(String(line[line.index(after: open)...]))
            word.raw.append(contentsOf: line[start...])
            word.value.append(contentsOf: line[start...])
            return line.endIndex
        }

        func backtick(at start: String.Index) -> String.Index {
            word.expands = true
            var cursor = line.index(after: start)
            var inner = ""
            while cursor < line.endIndex, line[cursor] != "`" {
                if line[cursor] == "\\", line.index(after: cursor) < line.endIndex {
                    inner.append(line[line.index(after: cursor)])
                    cursor = line.index(cursor, offsetBy: 2)
                    continue
                }
                inner.append(line[cursor])
                cursor = line.index(after: cursor)
            }
            result.substitutions.append(inner)
            let end = cursor < line.endIndex ? line.index(after: cursor) : line.endIndex
            if cursor == line.endIndex { result.complete = false }
            word.raw.append(contentsOf: line[start..<end])
            word.value.append(contentsOf: line[start..<end])
            return end
        }

        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if character == " " || character == "\t" {
                endWord(index)
                index = next
                continue
            }
            if character.isNewline {
                endWord(index)
                add(.separator("\n"), next)
                index = next
                continue
            }
            if character == "#", !inWord {
                while index < line.endIndex, !line[index].isNewline { index = line.index(after: index) }
                continue
            }
            if operatorCharacters.contains(character) {
                endWord(index)
                var end = next
                var symbol = String(character)
                if next < line.endIndex, doubleOperators.contains(symbol + String(line[next])) {
                    symbol += String(line[next])
                    end = line.index(after: next)
                    // &>> and <<< and <<-
                    if end < line.endIndex, (symbol == "&>" && line[end] == ">")
                        || (symbol == "<<" && (line[end] == "<" || line[end] == "-")) {
                        symbol += String(line[end])
                        end = line.index(after: end)
                    }
                }
                add(symbol.contains("<") || symbol.contains(">") ? .redirection(symbol) : .separator(symbol), end)
                index = end
                continue
            }
            if character == "~", !inWord { word.tilde = true }
            inWord = true
            switch character {
            case "\\":
                word.raw.append(character)
                guard next < line.endIndex else { index = next; continue }
                let escaped = line[next]
                word.raw.append(escaped)
                // A backslash before a line break joins the two lines.
                if !escaped.isNewline { word.value.append(escaped) }
                index = line.index(after: next)
            case "'":
                word.raw.append(character)
                var cursor = next
                while cursor < line.endIndex, line[cursor] != "'" {
                    word.raw.append(line[cursor])
                    word.value.append(line[cursor])
                    cursor = line.index(after: cursor)
                }
                if cursor < line.endIndex {
                    word.raw.append("'")
                    index = line.index(after: cursor)
                } else {
                    result.complete = false
                    index = cursor
                }
            case "\"":
                word.raw.append(character)
                var cursor = next
                var closed = false
                while cursor < line.endIndex {
                    let inner = line[cursor]
                    if inner == "\"" {
                        word.raw.append(inner)
                        cursor = line.index(after: cursor)
                        closed = true
                        break
                    }
                    if inner == "\\", line.index(after: cursor) < line.endIndex {
                        let escaped = line[line.index(after: cursor)]
                        word.raw.append(inner)
                        word.raw.append(escaped)
                        if "$`\"\\".contains(escaped) {
                            word.value.append(escaped)
                        } else if !escaped.isNewline {
                            word.value.append(inner)
                            word.value.append(escaped)
                        }
                        cursor = line.index(cursor, offsetBy: 2)
                        continue
                    }
                    if inner == "$" { cursor = dollar(at: cursor); continue }
                    if inner == "`" { cursor = backtick(at: cursor); continue }
                    word.raw.append(inner)
                    word.value.append(inner)
                    cursor = line.index(after: cursor)
                }
                if !closed { result.complete = false }
                index = cursor
            case "$":
                index = dollar(at: index)
            case "`":
                index = backtick(at: index)
            case "*", "?", "[", "{", "}":
                word.raw.append(character)
                word.value.append(character)
                word.expands = true
                index = next
            default:
                word.raw.append(character)
                word.value.append(character)
                index = next
            }
        }
        endWord(line.endIndex)
        return result
    }

    static func isNameCharacter(_ character: Character) -> Bool {
        character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
    }

    /// The index after the parenthesis that closes the one at `open`, skipping
    /// quoted text; nil when it never closes.
    static func matchingParenthesis(in line: String, from open: String.Index) -> String.Index? {
        var depth = 0
        var cursor = open
        while cursor < line.endIndex {
            switch line[cursor] {
            case "\\":
                cursor = line.index(after: cursor)
            case "'":
                cursor = line.index(after: cursor)
                while cursor < line.endIndex, line[cursor] != "'" { cursor = line.index(after: cursor) }
            case "\"":
                cursor = line.index(after: cursor)
                while cursor < line.endIndex, line[cursor] != "\"" {
                    if line[cursor] == "\\" { cursor = line.index(after: cursor) }
                    if cursor < line.endIndex { cursor = line.index(after: cursor) }
                }
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return line.index(after: cursor) }
            default:
                break
            }
            if cursor < line.endIndex { cursor = line.index(after: cursor) }
        }
        return nil
    }
}

// MARK: - No elevation

/// sudo, su and doas wherever a command can start: at the beginning, after
/// ; && || | & ( and line breaks, inside $(…) and backticks, behind wrappers
/// such as env, nohup or xargs, and in eval or `sh -c`. The island has no
/// way to take a password and never asks for one.
enum NotchTerminalElevation {
    static let commands: Set<String> = ["sudo", "sudoedit", "su", "doas"]
    /// Words that run the word after them as a command.
    private static let wrappers: Set<String> = [
        "command", "builtin", "exec", "nohup", "time", "noglob", "nocorrect", "nice", "env", "xargs",
        "timeout", "gtimeout", "caffeinate", "then", "do", "else", "elif", "if", "while", "until", "!", "{",
        "coproc",
    ]
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh"]

    static func requested(_ line: String) -> Bool {
        requested(line, depth: 0)
    }

    private static func requested(_ line: String, depth: Int) -> Bool {
        // Nesting this deep is no ordinary command; refusing is the safe answer.
        guard depth < 8 else { return true }
        let lexed = NotchTerminalShellWords.lex(line)
        if lexed.substitutions.contains(where: { requested($0, depth: depth + 1) }) { return true }
        var words: [NotchTerminalWord] = []
        var redirected = false
        for token in lexed.tokens {
            switch token {
            case .separator:
                if elevates(words, depth: depth) { return true }
                words = []
                redirected = false
            case .redirection:
                redirected = true
            case .word(let word):
                // The word after a redirection names its file.
                if redirected { redirected = false } else { words.append(word) }
            }
        }
        return elevates(words, depth: depth)
    }

    private static func elevates(_ words: [NotchTerminalWord], depth: Int) -> Bool {
        var wrapped = false
        for (index, word) in words.enumerated() {
            let value = word.value
            if isAssignment(value) { continue }
            let name = (value as NSString).lastPathComponent.lowercased()
            if wrappers.contains(name) {
                // `command -v sudo` only asks where sudo is.
                if name == "command", index + 1 < words.count, ["-v", "-V"].contains(words[index + 1].value) {
                    return false
                }
                wrapped = true
                continue
            }
            // A wrapper's own options and numbers, as in `nice -n 5` or `timeout 10`.
            if wrapped, value.hasPrefix("-") || (!value.isEmpty && value.allSatisfy(\.isNumber)) { continue }
            // macOS volumes ignore case, so SUDO finds /usr/bin/sudo.
            if commands.contains(name) { return true }
            let rest = words[(index + 1)...]
            if name == "eval" {
                return requested(rest.map(\.value).joined(separator: " "), depth: depth + 1)
            }
            if shells.contains(name),
               let flag = rest.firstIndex(where: { $0.value.hasPrefix("-") && !$0.value.hasPrefix("--") && $0.value.contains("c") }),
               flag + 1 < words.count {
                return requested(words[flag + 1].value, depth: depth + 1)
            }
            return false
        }
        return false
    }

    private static func isAssignment(_ value: String) -> Bool {
        guard let equals = value.firstIndex(of: "="), equals != value.startIndex else { return false }
        let name = value[..<equals]
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
            && !(name.first?.isNumber ?? true)
    }
}

// MARK: - cd

enum NotchTerminalDirectoryTarget: Equatable {
    case home
    /// `cd -`
    case previous
    /// As typed, relative to the current folder unless it starts with /.
    case path(String)
    /// A cd the island can't follow, and why.
    case invalid(String)
}

enum NotchTerminalCommand: Equatable {
    case empty
    /// sudo, su or doas, which the island never runs.
    case elevated
    /// A leading cd the island follows itself, so the folder carries over to
    /// the next command. What follows it runs in the new folder; after &&
    /// only once the change worked.
    case changeDirectory(NotchTerminalDirectoryTarget, then: String?, onlyIfChanged: Bool)
    case run(String)

    static func parse(_ line: String, home: String) -> NotchTerminalCommand {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if NotchTerminalElevation.requested(trimmed) { return .elevated }
        let lexed = NotchTerminalShellWords.lex(trimmed, variables: ["HOME": home])
        guard lexed.complete, case .word(let first)? = lexed.tokens.first, first.value == "cd", !first.expands
        else { return .run(trimmed) }
        var arguments: [NotchTerminalWord] = []
        var then: String?
        var onlyIfChanged = false
        tokens: for (index, token) in lexed.tokens.enumerated().dropFirst() {
            switch token {
            case .word(let word):
                arguments.append(word)
            case .redirection:
                // cd's own output sent somewhere: the shell does that best.
                return .run(trimmed)
            case .separator(let symbol):
                // Piped or sent to the background, a cd changes nothing the
                // next command sees, as in Terminal.
                guard symbol == "&&" || symbol == ";" || symbol == "\n" else { return .run(trimmed) }
                let rest = trimmed[lexed.ends[index]...].trimmingCharacters(in: .whitespacesAndNewlines)
                then = rest.isEmpty ? nil : rest
                onlyIfChanged = symbol == "&&" && then != nil
                break tokens
            }
        }
        return .changeDirectory(target(arguments, home: home), then: then, onlyIfChanged: onlyIfChanged)
    }

    private static func target(_ arguments: [NotchTerminalWord], home: String) -> NotchTerminalDirectoryTarget {
        var words = arguments[...]
        var optionsEnded = false
        // -L and -P choose how links are followed, -q and -s are zsh's quiet
        // and safe switches; the island always follows the path as written.
        while let first = words.first, !first.expands, first.raw == first.value {
            if first.value == "--" {
                words = words.dropFirst()
                optionsEnded = true
                break
            }
            guard first.value.count > 1, first.value.hasPrefix("-"),
                  first.value.dropFirst().allSatisfy({ "LPqse@".contains($0) }) else { break }
            words = words.dropFirst()
        }
        guard words.count <= 1 else { return .invalid(NotchTerminalText.tooManyArguments) }
        guard let word = words.first else { return .home }
        if word.raw == "-", !optionsEnded { return .previous }
        guard !word.expands else { return .invalid(NotchTerminalText.cannotExpand(word.raw)) }
        if word.tilde {
            if word.value == "~" { return .home }
            if word.value.hasPrefix("~/") { return .path(home + word.value.dropFirst()) }
            // Another person's home, ~name.
            return .invalid(NotchTerminalText.cannotExpand(word.raw))
        }
        // zsh reads -2 and +1 as places in its folder stack, which the island doesn't keep.
        if !optionsEnded, word.raw.hasPrefix("-") || word.raw.hasPrefix("+") {
            return .invalid(NotchTerminalText.cannotExpand(word.raw))
        }
        return .path(word.value)
    }
}

enum NotchTerminalPathKind: Equatable {
    case directory, notDirectory, missing, denied
}

enum NotchTerminalDirectory {
    enum Change: Equatable {
        /// The new folder; `announce` when the shell would print it, as after `cd -`.
        case changed(String, announce: Bool)
        case failed(String)
    }

    /// `.` and `..` worked out from the text alone, as cd does by default, so
    /// `..` from a linked folder goes back where it came from.
    static func normalized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    static func absolute(_ path: String, from current: String) -> String {
        normalized(path.hasPrefix("/") ? path : current + "/" + path)
    }

    static func change(_ target: NotchTerminalDirectoryTarget, current: String, previous: String?, home: String,
                       kind: (String) -> NotchTerminalPathKind) -> Change {
        let destination: String
        let label: String
        var announce = false
        switch target {
        case .invalid(let message):
            return .failed(message)
        case .home:
            destination = normalized(home)
            label = home
        case .previous:
            guard let previous else { return .failed(NotchTerminalText.noPreviousDirectory) }
            destination = previous
            label = previous
            announce = true
        case .path(let path):
            // `cd ""` stays where it is, as in zsh.
            destination = absolute(path, from: current)
            label = path
        }
        switch kind(destination) {
        case .directory: return .changed(destination, announce: announce)
        case .missing: return .failed(NotchTerminalText.noSuchDirectory(label))
        case .notDirectory: return .failed(NotchTerminalText.notDirectory(label))
        case .denied: return .failed(NotchTerminalText.permissionDenied(label))
        }
    }

    /// The prompt's folder, with the home folder as ~.
    static func display(_ path: String, home: String) -> String {
        let home = normalized(home)
        guard home != "/" else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Running

enum NotchTerminalShell {
    static let fallback = "/bin/zsh"

    /// The user's login shell from $SHELL, or zsh, macOS's own.
    static func path(environment: [String: String], isExecutable: (String) -> Bool) -> String {
        guard let shell = environment["SHELL"], shell.hasPrefix("/"), isExecutable(shell) else { return fallback }
        return shell
    }

    /// A login shell, so PATH and the rest come from the user's profile as in Terminal.
    static func arguments(for command: String) -> [String] {
        ["-l", "-c", command]
    }

    static func environment(base: [String: String], directory: String, previous: String?) -> [String: String] {
        var environment = base
        environment["PWD"] = directory
        environment["OLDPWD"] = previous
        // There is no terminal, and programs that look for one leave out
        // their colours and cursor tricks.
        environment["TERM"] = "dumb"
        return environment
    }
}

enum NotchTerminalExit: Equatable {
    case exited(Int32)
    case signaled(Int32)

    /// The line the scrollback ends a command with: none after success.
    func summary(stopped: Bool) -> String? {
        if stopped { return NotchTerminalText.stopped }
        switch self {
        case .exited(0): return nil
        case .exited(let code): return NotchTerminalText.exitStatus(code)
        case .signaled(let signal): return NotchTerminalText.endedBy(Self.signalName(signal))
        }
    }

    static func signalName(_ signal: Int32) -> String {
        let names: [Int32: String] = [
            1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE",
            9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE", 14: "SIGALRM", 15: "SIGTERM",
        ]
        return names[signal] ?? "signal \(signal)"
    }
}

/// Turns one stream of a command's bytes into lines of plain text. UTF-8
/// split between reads waits for the rest of its character. Escape sequences
/// for colour, the cursor or the window title are dropped, even when a read
/// ends inside one. A carriage return goes back to the start of the line and
/// a backspace one place left, so a progress bar ends as its last state and
/// overstruck text as itself; tabs stop every eight columns.
struct NotchTerminalStreamDecoder {
    /// A line with no break this long is broken here, so one runaway line
    /// can't grow without end.
    static let maximumLineLength = 4096
    /// An escape string that never ends gives up here and shows text again.
    static let maximumEscapeLength = 4096

    private enum State {
        case text, escape, escapeIntermediate, csi, osc, oscEscape, string, stringEscape
    }

    private var pendingBytes: [UInt8] = []
    private var state = State.text
    private var escapeLength = 0
    private var line: [Unicode.Scalar] = []
    private var column = 0

    init() {}

    /// The line still being written, nil while it is empty.
    var partialLine: String? {
        line.isEmpty ? nil : Self.string(line)
    }

    /// The lines these bytes complete.
    mutating func decode(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        var bytes = pendingBytes
        bytes.append(contentsOf: data)
        let cut = Self.completeLength(bytes)
        pendingBytes = Array(bytes[cut...])
        var lines: [String] = []
        for scalar in String(decoding: bytes[..<cut], as: UTF8.self).unicodeScalars {
            feed(scalar, into: &lines)
        }
        return lines
    }

    /// The stream ended: a character cut short reads as �, and the last line
    /// counts even without its break.
    mutating func finish() -> [String] {
        var lines: [String] = []
        if !pendingBytes.isEmpty {
            for scalar in String(decoding: pendingBytes, as: UTF8.self).unicodeScalars { feed(scalar, into: &lines) }
            pendingBytes = []
        }
        if !line.isEmpty { lines.append(Self.string(line)) }
        line = []
        column = 0
        state = .text
        escapeLength = 0
        return lines
    }

    /// Text as a terminal would leave it on screen, lines joined by \n.
    static func plainText(_ text: String) -> String {
        var decoder = NotchTerminalStreamDecoder()
        return (decoder.decode(Data(text.utf8)) + decoder.finish()).joined(separator: "\n")
    }

    /// How many bytes from the start end on a whole UTF-8 character.
    static func completeLength(_ bytes: [UInt8]) -> Int {
        var index = bytes.count - 1
        let earliest = max(0, bytes.count - 4)
        while index >= earliest {
            let byte = bytes[index]
            if byte & 0xC0 != 0x80 {
                let length = byte & 0x80 == 0 ? 1 : byte & 0xE0 == 0xC0 ? 2 : byte & 0xF0 == 0xE0 ? 3
                    : byte & 0xF8 == 0xF0 ? 4 : 1
                return bytes.count - index < length ? index : bytes.count
            }
            index -= 1
        }
        return bytes.count
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private mutating func feed(_ scalar: Unicode.Scalar, into lines: inout [String]) {
        let value = scalar.value
        switch state {
        case .text:
            break
        case .escape:
            switch value {
            case 0x5B: enter(.csi)                          // [
            case 0x5D: enter(.osc)                          // ]
            case 0x50, 0x58, 0x5E, 0x5F: enter(.string)     // P X ^ _
            case 0x1B: return
            case 0x20...0x2F: enter(.escapeIntermediate)
            case 0x30...0x7E: state = .text
            default:
                state = .text
                feed(scalar, into: &lines)
            }
            return
        case .escapeIntermediate:
            switch value {
            case 0x20...0x2F: return
            case 0x30...0x7E: state = .text
            default:
                state = .text
                feed(scalar, into: &lines)
            }
            return
        case .csi:
            switch value {
            case 0x20...0x3F: escaped()
            case 0x40...0x7E: state = .text
            case 0x1B: state = .escape
            default:
                state = .text
                feed(scalar, into: &lines)
            }
            return
        case .osc:
            switch value {
            case 0x07, 0x9C: state = .text
            case 0x1B: state = .oscEscape
            default: escaped()
            }
            return
        case .oscEscape:
            if value == 0x5C {
                state = .text
            } else {
                state = .escape
                feed(scalar, into: &lines)
            }
            return
        case .string:
            switch value {
            case 0x9C: state = .text
            case 0x1B: state = .stringEscape
            default: escaped()
            }
            return
        case .stringEscape:
            state = value == 0x5C ? .text : .string
            return
        }
        switch value {
        case 0x1B: enter(.escape)
        case 0x9B: enter(.csi)
        case 0x9D: enter(.osc)
        case 0x90, 0x98, 0x9E, 0x9F: enter(.string)
        case 0x0A:
            lines.append(Self.string(line))
            line = []
            column = 0
        case 0x0D:
            column = 0
        case 0x08:
            column = max(0, column - 1)
        case 0x09:
            let stop = (column / 8 + 1) * 8
            while column < stop { put(" ", into: &lines) }
        case 0x00...0x1F, 0x7F...0x9F:
            break
        default:
            put(scalar, into: &lines)
        }
    }

    private mutating func enter(_ next: State) {
        state = next
        escapeLength = 0
    }

    private mutating func escaped() {
        escapeLength += 1
        if escapeLength > Self.maximumEscapeLength { state = .text }
    }

    private mutating func put(_ scalar: Unicode.Scalar, into lines: inout [String]) {
        if column >= Self.maximumLineLength {
            lines.append(Self.string(line))
            line = []
            column = 0
        }
        if column < line.count {
            line[column] = scalar
        } else {
            line.append(scalar)
        }
        column += 1
    }
}
