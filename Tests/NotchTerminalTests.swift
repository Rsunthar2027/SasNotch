// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The island terminal's pure parts: reading a leading cd and following it,
/// refusing sudo, cleaning a command's output, the scrollback's cap, the
/// history, the prompt's folder, and how the feature and its page are set up.
enum NotchTerminalTests {
    private static let home = "/Users/sasquatch"

    static func run(_ suite: TestSuite) {
        changeDirectoryParsing(suite)
        changeDirectoryResolution(suite)
        elevation(suite)
        ansiStripping(suite)
        streamDecoding(suite)
        scrollback(suite)
        history(suite)
        promptPath(suite)
        keys(suite)
        shell(suite)
        exitSummary(suite)
        feature(suite)
    }

    private static func parse(_ line: String) -> NotchTerminalCommand {
        NotchTerminalCommand.parse(line, home: home)
    }

    private static func cd(_ target: NotchTerminalDirectoryTarget, then: String? = nil,
                           onlyIfChanged: Bool = false) -> NotchTerminalCommand {
        .changeDirectory(target, then: then, onlyIfChanged: onlyIfChanged)
    }

    // MARK: cd

    private static func changeDirectoryParsing(_ suite: TestSuite) {
        suite.expect(parse("") == .empty && parse("   \n\t ") == .empty, "a blank line runs nothing")
        suite.expect(parse("ls -la") == .run("ls -la") && parse("  git status  ") == .run("git status"),
                     "anything that isn't a cd runs in the shell, trimmed")
        suite.expect(parse("cd") == cd(.home) && parse("cd ~") == cd(.home) && parse("cd   ") == cd(.home),
                     "cd and cd ~ go home")
        suite.expect(parse("cd ~/Projects") == cd(.path(home + "/Projects")), "~/ is the home folder")
        suite.expect(parse("cd -") == cd(.previous), "cd - goes back to the previous folder")
        suite.expect(parse("cd ..") == cd(.path("..")) && parse("cd src/app") == cd(.path("src/app"))
                        && parse("cd /tmp") == cd(.path("/tmp")),
                     "relative and absolute paths are kept as typed")
        suite.expect(parse("cd 'My Folder'") == cd(.path("My Folder"))
                        && parse("cd \"My Folder\"") == cd(.path("My Folder"))
                        && parse("cd My\\ Folder") == cd(.path("My Folder"))
                        && parse("cd \"it's here\"") == cd(.path("it's here"))
                        && parse("cd 'a\"b'") == cd(.path("a\"b")),
                     "single quotes, double quotes and backslashes keep spaces and quotes in a path")
        suite.expect(parse("cd '~'") == cd(.path("~")) && parse("cd \"~/x\"") == cd(.path("~/x")),
                     "a quoted ~ is just a folder named ~")
        suite.expect(parse("cd $HOME") == cd(.path(home)) && parse("cd \"$HOME/Library\"") == cd(.path(home + "/Library"))
                        && parse("cd ${HOME}/Desktop") == cd(.path(home + "/Desktop")),
                     "$HOME and ${HOME} are the home folder")
        suite.expect(parse("cd -P /tmp") == cd(.path("/tmp")) && parse("cd -L ..") == cd(.path(".."))
                        && parse("cd -- -dash") == cd(.path("-dash")) && parse("cd -q") == cd(.home),
                     "cd's own options are read past, and -- ends them")
        suite.expect(parse("cd a b") == cd(.invalid(NotchTerminalText.tooManyArguments)),
                     "two folders at once is an error")
        for unexpandable in ["$PROJECTS", "*", "src/*", "{a,b}", "$(pwd)", "`pwd`", "~bob", "-2", "+1"] {
            suite.expect(parse("cd \(unexpandable)") == cd(.invalid(NotchTerminalText.cannotExpand(unexpandable))),
                         "cd \(unexpandable) is refused rather than guessed at")
        }
        suite.expect(parse("cd src && make") == cd(.path("src"), then: "make", onlyIfChanged: true),
                     "after && the rest runs in the new folder only if the cd worked")
        suite.expect(parse("cd src; ls -a") == cd(.path("src"), then: "ls -a")
                        && parse("cd src\nls") == cd(.path("src"), then: "ls"),
                     "after ; or a line break the rest runs either way")
        suite.expect(parse("cd a && cd b && pwd") == cd(.path("a"), then: "cd b && pwd", onlyIfChanged: true),
                     "a following cd is left for the next round, so it is followed too")
        suite.expect(parse("cd src;") == cd(.path("src")) && parse("cd src && ") == cd(.path("src")),
                     "a separator with nothing after it runs nothing more")
        for shellOnly in ["cd src | cat", "cd src || echo no", "cd src &", "cd src > /dev/null", "cd 'open",
                          "x=1 cd src", "(cd src)", "\"$CD\" src"] {
            suite.expect(parse(shellOnly) == .run(shellOnly), "\(shellOnly) is left to the shell")
        }
        suite.expect(parse("cdx src") == .run("cdx src") && parse("echo cd") == .run("echo cd"),
                     "only the cd command itself is followed")
        suite.expect(parse("cd src # notes") == cd(.path("src")), "a comment is not an argument")
    }

    private static func changeDirectoryResolution(_ suite: TestSuite) {
        let folders: Set<String> = ["/", "/tmp", home, home + "/Projects", home + "/My Folder", "/Volumes/Data"]
        let files: Set<String> = [home + "/notes.txt"]
        let locked: Set<String> = ["/private/root"]
        func kind(_ path: String) -> NotchTerminalPathKind {
            folders.contains(path) ? .directory : files.contains(path) ? .notDirectory
                : locked.contains(path) ? .denied : .missing
        }
        func change(_ target: NotchTerminalDirectoryTarget, from current: String = home,
                    previous: String? = nil) -> NotchTerminalDirectory.Change {
            NotchTerminalDirectory.change(target, current: current, previous: previous, home: home, kind: kind)
        }
        suite.expect(change(.home, from: "/tmp") == .changed(home, announce: false), "home is home")
        suite.expect(change(.path("Projects")) == .changed(home + "/Projects", announce: false)
                        && change(.path("My Folder")) == .changed(home + "/My Folder", announce: false),
                     "a relative path starts at the current folder")
        suite.expect(change(.path(".."), from: home + "/Projects") == .changed(home, announce: false)
                        && change(.path("../.."), from: "/tmp") == .changed("/", announce: false)
                        && change(.path("./Projects/../Projects/")) == .changed(home + "/Projects", announce: false),
                     ". and .. are worked out from the path, never above /")
        suite.expect(change(.path("/Volumes/Data"), from: "/tmp") == .changed("/Volumes/Data", announce: false)
                        && change(.path("//tmp//")) == .changed("/tmp", announce: false),
                     "an absolute path stands alone, extra slashes and all")
        suite.expect(change(.previous, from: "/tmp", previous: home) == .changed(home, announce: true),
                     "cd - returns to the previous folder and says where, as the shell does")
        suite.expect(change(.previous) == .failed(NotchTerminalText.noPreviousDirectory),
                     "cd - before any other cd has nowhere to go")
        suite.expect(change(.path("Nope")) == .failed(NotchTerminalText.noSuchDirectory("Nope")),
                     "a folder that doesn't exist is reported by the name typed")
        suite.expect(change(.path("notes.txt")) == .failed(NotchTerminalText.notDirectory("notes.txt")),
                     "a file is not a folder")
        suite.expect(change(.path("/private/root")) == .failed(NotchTerminalText.permissionDenied("/private/root")),
                     "a folder that can't be entered says so")
        suite.expect(change(.invalid("why")) == .failed("why"), "a cd that couldn't be read fails with its reason")
        suite.expect(change(.path(""), from: "/tmp") == .changed("/tmp", announce: false), "cd \"\" stays put")
        suite.expect(NotchTerminalDirectory.absolute("a/b", from: "/") == "/a/b"
                        && NotchTerminalDirectory.normalized("") == "/"
                        && NotchTerminalDirectory.normalized("/a/./b/../c") == "/a/c",
                     "paths come out absolute and tidy")
    }

    // MARK: Elevation

    private static func elevation(_ suite: TestSuite) {
        let refused = [
            "sudo ls", "sudo", "su", "su -", "doas reboot", "sudoedit /etc/hosts", "  sudo   rm -rf /tmp/x",
            "ls && sudo rm x", "true; sudo ls", "false || sudo ls", "ls | sudo tee /etc/x", "sleep 1 & sudo ls",
            "(sudo ls)", "{ sudo ls; }", "if true; then sudo ls; fi", "echo $(sudo id)", "echo `sudo id`",
            "echo \"$(sudo id)\"", "FOO=1 sudo ls", "env -i PATH=/bin sudo ls", "nice -n 5 sudo ls",
            "nohup sudo ls", "exec sudo ls", "command sudo ls", "time sudo ls", "xargs sudo rm",
            "timeout 10 sudo ls", "/usr/bin/sudo ls", "SUDO ls", "'sudo' ls", "\"su\"", "s\\udo ls",
            "eval sudo ls", "eval 'sudo ls'", "bash -c 'sudo ls'", "zsh -lc \"doas ls\"", "sh -x -c 'su'",
            "echo $(echo $(sudo ls))", "ls\nsudo ls",
        ]
        for line in refused {
            suite.expect(NotchTerminalElevation.requested(line) && parse(line) == .elevated, "\(line) is refused")
        }
        let allowed = [
            "ls", "echo sudo", "echo 'sudo ls'", "git commit -m \"sudo fix\"", "man sudo", "which sudo",
            "command -v sudo", "sum file", "sudoku", "summary", "subl .", "cat /etc/sudoers", "ls > sudo",
            "grep -r doas .", "bash script.sh", "sh -c 'ls'", "echo su",
        ]
        for line in allowed {
            suite.expect(!NotchTerminalElevation.requested(line), "\(line) is not elevation")
        }
        suite.expect(parse("cd /tmp && sudo ls") == .elevated, "a cd doesn't hide a sudo after it")
    }

    // MARK: Output

    private static func ansiStripping(_ suite: TestSuite) {
        let plain = NotchTerminalStreamDecoder.plainText
        suite.expect(plain("\u{1B}[31mred\u{1B}[0m and \u{1B}[1;38;5;208mbold\u{1B}[m") == "red and bold",
                     "colour and style sequences go")
        suite.expect(plain("\u{1B}[2K\u{1B}[1Gdone\u{1B}[?25h") == "done", "cursor and erase sequences go")
        suite.expect(plain("\u{1B}]0;window title\u{07}text") == "text"
                        && plain("\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\") == "link",
                     "title and hyperlink sequences go, ended by BEL or ST")
        suite.expect(plain("\u{1B}(Bcharset\u{1B}=keypad\u{1B}7saved") == "charsetkeypadsaved",
                     "charset and other short escapes go")
        suite.expect(plain("\u{1B}P1$r0m\u{1B}\\after") == "after", "device control strings go")
        suite.expect(plain("\u{9B}31mC1\u{9B}0m") == "C1", "the one-byte CSI goes too")
        suite.expect(plain("bell\u{07} null\u{00} del\u{7F}") == "bell null del", "stray control characters go")
        suite.expect(plain("progress 10%\rprogress 55%\rprogress 100%") == "progress 100%"
                        && plain("hello\rj") == "jello",
                     "a carriage return goes back to the start of the line and overwrites")
        suite.expect(plain("crlf\r\nnext") == "crlf\nnext", "CRLF is one line break")
        suite.expect(plain("b\u{8}bo\u{8}ol\u{8}ld\u{8}d") == "bold" && plain("ab\u{8}\u{8}xy") == "xy",
                     "a backspace steps back one place, so overstruck text reads as itself")
        suite.expect(plain("a\tb") == "a       b" && plain("1234567\tx") == "1234567 x"
                        && plain("12345678\tx") == "12345678        x",
                     "tabs stop every eight columns")
        suite.expect(plain("café ☕ ünïcödé") == "café ☕ ünïcödé", "text that is just text stays as it is")
        suite.expect(plain("one\n\nthree\n") == "one\n\nthree", "empty lines stay, a final break adds none")
    }

    private static func streamDecoding(_ suite: TestSuite) {
        var decoder = NotchTerminalStreamDecoder()
        suite.expect(decoder.decode(Data("abc\u{1B}[3".utf8)).isEmpty && decoder.partialLine == "abc",
                     "an unfinished line is offered as the partial line")
        suite.expect(decoder.decode(Data("1mdef\nghi".utf8)) == ["abcdef"] && decoder.partialLine == "ghi",
                     "an escape sequence split between reads still goes")
        suite.expect(decoder.finish() == ["ghi"] && decoder.partialLine == nil,
                     "the end of the stream keeps a last line without a break")

        var split = NotchTerminalStreamDecoder()
        let euro = Array("€ ok\n".utf8)
        suite.expect(split.decode(Data(euro[0..<1])).isEmpty && split.decode(Data(euro[1..<2])).isEmpty
                        && split.decode(Data(euro[2...])) == ["€ ok"],
                     "a character split between reads waits for its last byte")
        var cut = NotchTerminalStreamDecoder()
        _ = cut.decode(Data([0x61, 0xE2, 0x82]))
        suite.expect(cut.finish() == ["a\u{FFFD}"], "a character cut off by the end reads as a replacement")
        suite.expect(NotchTerminalStreamDecoder.completeLength([0x61, 0xF0, 0x9F, 0x98]) == 1
                        && NotchTerminalStreamDecoder.completeLength([0x61, 0xF0, 0x9F, 0x98, 0x80]) == 5
                        && NotchTerminalStreamDecoder.completeLength([]) == 0
                        && NotchTerminalStreamDecoder.completeLength([0x80, 0x80, 0x80, 0x80, 0x80]) == 5,
                     "only a lead byte still waiting for its continuation bytes is held back")

        var long = NotchTerminalStreamDecoder()
        let lines = long.decode(Data(String(repeating: "x", count: NotchTerminalStreamDecoder.maximumLineLength * 2 + 5).utf8))
        suite.expect(lines.count == 2 && lines.allSatisfy { $0.count == NotchTerminalStreamDecoder.maximumLineLength }
                        && long.partialLine?.count == 5,
                     "a line with no break is broken at the limit")
        var runaway = NotchTerminalStreamDecoder()
        _ = runaway.decode(Data(("\u{1B}]" + String(repeating: "t", count: NotchTerminalStreamDecoder.maximumEscapeLength + 10)
                                 + "visible\n").utf8))
        suite.expect(runaway.finish().isEmpty && runaway.decode(Data("next\n".utf8)) == ["next"],
                     "a title sequence that never ends gives way to text again")
        var cleared = NotchTerminalStreamDecoder()
        _ = cleared.decode(Data("\u{1B}[31".utf8))
        _ = cleared.finish()
        suite.expect(cleared.decode(Data("m?\n".utf8)) == ["m?"], "finishing forgets an open escape")
    }

    private static func scrollback(_ suite: TestSuite) {
        var lines = NotchTerminalScrollback()
        suite.expect(lines.limit == 2000 && NotchTerminalScrollback.defaultLimit == 2000 && lines.isEmpty,
                     "the scrollback holds about 2,000 lines")
        for number in 0..<2500 { lines.append(.output, "line \(number)") }
        suite.expect(lines.lines.count == 2000 && lines.lines.first?.text == "line 500"
                        && lines.lines.last?.text == "line 2499",
                     "past the cap the oldest lines go first")
        suite.expect(Set(lines.lines.map(\.id)).count == 2000 && lines.lines.first?.id == 500 && lines.nextID == 2500,
                     "every line keeps its own id")
        lines.append((0..<5000).map { (kind: NotchTerminalLineKind.error, text: "burst \($0)") })
        suite.expect(lines.lines.count == 2000 && lines.lines.first?.text == "burst 3000"
                        && lines.lines.allSatisfy { $0.kind == .error } && lines.nextID == 7500,
                     "a burst bigger than the scrollback keeps its own end")
        lines.clear()
        lines.append(.command, "~ % ls")
        suite.expect(lines.lines.count == 1 && lines.lines[0].id == 7500 && lines.lines[0].kind == .command,
                     "ids keep counting after a clear")
        var tiny = NotchTerminalScrollback(limit: 0)
        tiny.append(.output, "a")
        tiny.append(.output, "b")
        suite.expect(tiny.limit == 1 && tiny.lines.map(\.text) == ["b"], "a scrollback always keeps its last line")
    }

    private static func history(_ suite: TestSuite) {
        var history = NotchTerminalHistory()
        suite.expect(history.older(than: "typing") == nil && history.newer() == nil, "no history, no recall")
        for command in ["ls", "  ", "git status", "git status", "make "] { history.record(command) }
        suite.expect(history.entries == ["ls", "git status", "make"],
                     "blank lines and an immediate repeat aren't kept")
        suite.expect(history.older(than: "draft") == "make" && history.older(than: "make") == "git status"
                        && history.older(than: "git status") == "ls" && history.older(than: "ls") == nil
                        && history.isBrowsing,
                     "Up walks back to the oldest and stops there")
        suite.expect(history.newer() == "git status" && history.newer() == "make" && history.newer() == "draft"
                        && history.newer() == nil && !history.isBrowsing,
                     "Down walks forward and ends at what was being typed")
        history.record("ls")
        suite.expect(history.entries.last == "ls" && history.entries.count == 4 && !history.isBrowsing,
                     "a command run again goes to the end")
        for number in 0..<300 { history.record("echo \(number)") }
        suite.expect(history.entries.count == NotchTerminalHistory.limit && history.entries.last == "echo 299",
                     "history keeps the newest \(NotchTerminalHistory.limit)")
        history.clear()
        suite.expect(history.entries.isEmpty && history.older(than: "") == nil, "clearing forgets it all")
    }

    private static func promptPath(_ suite: TestSuite) {
        let display = { NotchTerminalDirectory.display($0, home: home) }
        suite.expect(display(home) == "~" && display(home + "/Projects/app") == "~/Projects/app",
                     "the home folder reads as ~")
        suite.expect(display("/Users/sasquatchy") == "/Users/sasquatchy" && display("/tmp") == "/tmp"
                        && display("/") == "/" && display("/Users") == "/Users",
                     "only the home folder itself, not a folder named like it, is shortened")
        suite.expect(NotchTerminalDirectory.display(home + "/x", home: home + "/") == "~/x"
                        && NotchTerminalDirectory.display("/x", home: "/") == "/x",
                     "a home written with a trailing slash still matches, and / as home shortens nothing")
        suite.expect(NotchTerminalSupport.promptSymbol(shell: "/bin/zsh") == "%"
                        && NotchTerminalSupport.promptSymbol(shell: "/opt/homebrew/bin/bash") == "$"
                        && NotchTerminalSupport.promptSymbol(shell: "/bin/sh") == "$",
                     "the prompt ends in the mark the login shell uses")
    }

    private static func keys(_ suite: TestSuite) {
        func key(_ code: UInt16, _ characters: String = "", command: Bool = false, control: Bool = false,
                 option: Bool = false, shift: Bool = false) -> NotchTerminalKey? {
            NotchTerminalKey(keyCode: code, characters: characters, command: command, control: control,
                             option: option, shift: shift)
        }
        suite.expect(key(126) == .older && key(125) == .newer && key(36) == .submit && key(76) == .submit,
                     "Up, Down, Return and Enter belong to the prompt")
        suite.expect(key(8, "c", control: true) == .interrupt && key(37, "l", control: true) == .clear
                        && key(34, "c", control: true) == .interrupt,
                     "Control-C stops and Control-L clears, by character on any layout")
        suite.expect(key(126, shift: true) == nil && key(36, command: true) == nil && key(36, option: true) == nil
                        && key(8, "c", command: true) == nil && key(8, "c", control: true, shift: true) == nil
                        && key(53) == nil && key(48) == nil && key(0, "a") == nil,
                     "Escape, Tab, typing and modified keys go on as usual")
    }

    private static func shell(_ suite: TestSuite) {
        let executable: (String) -> Bool = { ["/bin/zsh", "/bin/bash", "/opt/homebrew/bin/fish"].contains($0) }
        suite.expect(NotchTerminalShell.path(environment: ["SHELL": "/opt/homebrew/bin/fish"], isExecutable: executable)
                        == "/opt/homebrew/bin/fish"
                        && NotchTerminalShell.path(environment: ["SHELL": "/bin/bash"], isExecutable: executable) == "/bin/bash",
                     "the login shell is $SHELL")
        suite.expect(NotchTerminalShell.path(environment: [:], isExecutable: executable) == "/bin/zsh"
                        && NotchTerminalShell.path(environment: ["SHELL": ""], isExecutable: executable) == "/bin/zsh"
                        && NotchTerminalShell.path(environment: ["SHELL": "zsh"], isExecutable: executable) == "/bin/zsh"
                        && NotchTerminalShell.path(environment: ["SHELL": "/gone/shell"], isExecutable: executable) == "/bin/zsh",
                     "a missing, relative or absent $SHELL falls back to zsh")
        suite.expect(NotchTerminalShell.arguments(for: "ls -la | head") == ["-l", "-c", "ls -la | head"],
                     "each command runs in a login shell, whole")
        let environment = NotchTerminalShell.environment(base: ["PATH": "/usr/bin", "OLDPWD": "/stale", "TERM": "xterm"],
                                                         directory: "/tmp", previous: nil)
        suite.expect(environment["PATH"] == "/usr/bin" && environment["PWD"] == "/tmp" && environment["OLDPWD"] == nil
                        && environment["TERM"] == "dumb",
                     "the user's environment goes along, with the folder and no terminal to draw on")
        suite.expect(NotchTerminalShell.environment(base: [:], directory: "/a", previous: "/b")["OLDPWD"] == "/b",
                     "the previous folder is OLDPWD")
    }

    private static func exitSummary(_ suite: TestSuite) {
        suite.expect(NotchTerminalExit.exited(0).summary(stopped: false) == nil, "success says nothing")
        suite.expect(NotchTerminalExit.exited(1).summary(stopped: false) == "Exit status 1"
                        && NotchTerminalExit.exited(127).summary(stopped: false) == "Exit status 127",
                     "any other exit status is shown")
        suite.expect(NotchTerminalExit.signaled(11).summary(stopped: false) == "Ended by SIGSEGV"
                        && NotchTerminalExit.signaled(31).summary(stopped: false) == "Ended by signal 31",
                     "a signal is named")
        suite.expect(NotchTerminalExit.exited(130).summary(stopped: true) == NotchTerminalText.stopped
                        && NotchTerminalExit.signaled(2).summary(stopped: true) == NotchTerminalText.stopped
                        && NotchTerminalExit.exited(0).summary(stopped: true) == NotchTerminalText.stopped,
                     "a command stopped from the page just says Stopped")
    }

    // MARK: Feature

    private static func feature(_ suite: TestSuite) {
        let feature = AppFeature.notchTerminal
        suite.expect(feature.group == .dynamicIsland && feature.symbolName == "terminal"
                        && feature.enabledKeys.isEmpty && feature.permissions.isEmpty
                        && feature.onboardingPermissions.isEmpty && feature.energyProfile == .idle
                        && !feature.monitorsPermissionChanges(boolFor: { _ in false })
                        && feature.settingsDestination == FeatureSettingsDestination(.notch)
                        && FeatureVisibilitySupport.features(for: .notch).contains(feature),
                     "the terminal is an island extension that asks for no permission and costs nothing at rest")
        suite.expect(!feature.installedByDefault && !feature.isLocked && feature.hubSection == .advanced
                        && AppFeature.advancedFeatures.contains(feature)
                        && !FeaturePreset.essential.features.contains(feature)
                        && !FeaturePreset.allCases.contains { $0.features.contains(feature) }
                        && !AppFeature.notch.initialInstallGroup.contains(feature)
                        && AppFeature.dynamicIslandExtensions.contains(feature),
                     "it waits under Advanced: no preset or island install brings it, one click does")
        suite.expect(NotchModule.terminal.symbol == "terminal" && NotchModule.terminal.shortcutKey == "x"
                        && NotchModule.terminal.pageTop == .row,
                     "the page is Terminal, ⌥⌘X")
        let keys = NotchModule.allCases.map(\.shortcutKey)
        suite.expect(Set(keys).count == keys.count && !keys.contains("o"),
                     "every page keeps its own key, and Watch's old ⌥⌘O stays free")
        suite.expect(NotchSupport.moduleShortcut("X", modules: NotchModule.allCases) == .terminal,
                     "⌥⌘X opens the terminal")

        let domain = "com.sasnotch.tests.notch-terminal"
        guard let defaults = UserDefaults(suiteName: domain) else {
            suite.expect(false, "terminal defaults suite can be created")
            return
        }
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for feature in AppFeature.allCases { defaults.set(feature.installedByDefault, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchModule.terminal.isAvailable(in: defaults) && !NotchSupport.modules(in: defaults).contains(.terminal)
                        && !NotchTerminalSupport.isEnabled(in: defaults),
                     "until it is installed the island has no terminal page")
        defaults.set(true, forKey: feature.availabilityKey)
        suite.expect(NotchSupport.modules(in: defaults).last == .terminal && NotchTerminalSupport.isEnabled(in: defaults),
                     "installing it adds the page, last, with nothing else to switch on")
        defaults.set("terminal", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchTerminalSupport.isEnabled(in: defaults), "hiding the page turns the terminal off")
        defaults.removeObject(forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchTerminalSupport.isEnabled(in: defaults), "turning the island off turns the terminal off")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(false, forKey: feature.availabilityKey)
        suite.expect(!NotchTerminalSupport.isEnabled(in: defaults), "uninstalling it turns it off")
    }
}
