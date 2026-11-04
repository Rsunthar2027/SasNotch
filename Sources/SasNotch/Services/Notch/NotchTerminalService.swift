// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import AppKit
import Combine
import Foundation

/// What the page's list draws, apart from the service, so a command pouring
/// out lines redraws the list and not the island around it.
final class NotchTerminalOutput: ObservableObject {
    @Published fileprivate(set) var scrollback = NotchTerminalScrollback()
    /// The last line of each stream while it has no line break yet, such as a
    /// progress bar, shown under the scrollback until it ends.
    @Published fileprivate(set) var partialLines: [NotchTerminalLine] = []

    var isEmpty: Bool { scrollback.isEmpty && partialLines.isEmpty }
}

/// Runs the island terminal's commands, one at a time, as the user in their
/// login shell with nothing on stdin, and keeps the scrollback, the history
/// and the folder between them. It reads a command's output only while that
/// command runs; with nothing running it holds no timer, process or file.
/// Like the other island services it lives on the main thread; the pipes are
/// read on their own queue and hand their lines over in batches.
final class NotchTerminalService: ObservableObject {
    static let shared = NotchTerminalService()

    let output = NotchTerminalOutput()
    /// Whether Clear has anything to clear.
    @Published private(set) var hasOutput = false
    @Published private(set) var directory: String
    @Published private(set) var running = false
    /// Stop was pressed and the command hasn't ended yet.
    @Published private(set) var stopping = false
    /// What the prompt held when the page closed, for the next opening.
    var draft = ""
    private(set) var history = NotchTerminalHistory()

    let shell: String
    private let home: String
    private var previousDirectory: String?
    private var current: Run?
    /// Decoding happens here, so a command that prints fast never holds up the island.
    private let queue = DispatchQueue(label: "com.sasnotch.notch-terminal", qos: .userInitiated)
    /// Batches reach the scrollback at most this often while output pours in.
    private static let flushDelay: TimeInterval = 0.05
    /// After the shell exits, a background job may keep its pipes open; the
    /// island stops listening this long after.
    private static let drainDelay: TimeInterval = 0.5
    /// Stop asks with SIGINT, as Control-C does, then insists with SIGTERM
    /// and finally SIGKILL, each this long after the one before.
    private static let escalationDelay: TimeInterval = 2

    private init() {
        home = NotchTerminalDirectory.normalized(NSHomeDirectory())
        directory = home
        shell = NotchTerminalShell.path(environment: ProcessInfo.processInfo.environment,
                                        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    var displayDirectory: String { NotchTerminalDirectory.display(directory, home: home) }
    var promptSymbol: String { NotchTerminalSupport.promptSymbol(shell: shell) }

    // MARK: Island lifecycle

    /// Turning the page off ends what runs there and forgets what it showed.
    func syncWithPreferences() {
        if !NotchTerminalSupport.isEnabled() { stop() }
    }

    func stop() {
        if let run = current {
            terminate(run)
            // Its end has nothing left to report to.
            current = nil
            running = false
            stopping = false
        }
        guard !output.isEmpty || !history.entries.isEmpty || !draft.isEmpty || directory != home else { return }
        clear()
        history.clear()
        draft = ""
        previousDirectory = nil
        directory = home
    }

    /// The app is quitting: nothing it started may outlive it, and there is no
    /// time to ask twice.
    func terminateForQuit() {
        guard let run = current, run.process.isRunning else { return }
        signal(run, SIGTERM)
        let deadline = Date().addingTimeInterval(0.3)
        while run.process.isRunning, Date() < deadline { usleep(10_000) }
        // The whole group, in case the shell went and a program in it stayed.
        if let group = run.group { kill(-group, SIGKILL) } else { signal(run, SIGKILL) }
    }

    // MARK: Prompt

    /// Runs what was typed at the prompt. Return while a command runs does
    /// nothing but beep: there is no stdin to send it to.
    func submit(_ text: String) {
        guard current == nil else { NSSound.beep(); return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history.record(trimmed)
        say(.command, "\(displayDirectory) \(promptSymbol) \(trimmed)")
        perform(trimmed)
    }

    func olderCommand(than current: String) -> String? { history.older(than: current) }
    func newerCommand() -> String? { history.newer() }

    func clear() {
        output.scrollback.clear()
        output.partialLines = []
        noteOutput()
    }

    private func say(_ kind: NotchTerminalLineKind, _ text: String) {
        output.scrollback.append(kind, text)
        noteOutput()
    }

    private func noteOutput() {
        if hasOutput == output.isEmpty { hasOutput = !output.isEmpty }
    }

    /// Stop: SIGINT to the command's process group, then SIGTERM.
    func interrupt() {
        guard let run = current, !run.stopRequested else { return }
        run.stopRequested = true
        stopping = true
        signal(run, SIGINT)
        escalate(run, to: [SIGTERM, SIGKILL])
    }

    func openInTerminal() {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            say(.notice, NotchTerminalText.noTerminal)
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.say(.notice, NotchTerminalText.noTerminal) }
        }
    }

    // MARK: Running

    private func perform(_ line: String) {
        switch NotchTerminalCommand.parse(line, home: home) {
        case .empty:
            return
        case .elevated:
            say(.notice, NotchTerminalText.elevationBlocked)
        case .run(let command):
            start(command)
        case .changeDirectory(let target, let then, let onlyIfChanged):
            let change = NotchTerminalDirectory.change(target, current: directory, previous: previousDirectory,
                                                       home: home, kind: Self.kind)
            var changed = false
            switch change {
            case .changed(let destination, let announce):
                if destination != directory {
                    previousDirectory = directory
                    directory = destination
                }
                if announce { say(.output, displayDirectory) }
                changed = true
            case .failed(let message):
                say(.error, message)
            }
            // What follows may be another cd, so it goes through here again.
            if let then, changed || !onlyIfChanged { perform(then) }
        }
    }

    private func start(_ command: String) {
        if Self.kind(directory) != .directory {
            say(.notice, NotchTerminalText.folderGone(displayDirectory))
            previousDirectory = nil
            directory = home
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = NotchTerminalShell.arguments(for: command)
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.environment = NotchTerminalShell.environment(base: ProcessInfo.processInfo.environment,
                                                             directory: directory, previous: previousDirectory)
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let run = Run(process: process, output: output.fileHandleForReading, errors: errors.fileHandleForReading)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.received(handle.availableData, error: false, run: run)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.received(handle.availableData, error: true, run: run)
        }
        process.terminationHandler = { [weak self] process in
            let exit: NotchTerminalExit = process.terminationReason == .uncaughtSignal
                ? .signaled(process.terminationStatus) : .exited(process.terminationStatus)
            self?.exited(exit, run: run)
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            say(.error, NotchTerminalText.launchFailed(error.localizedDescription))
            return
        }
        let pid = process.processIdentifier
        if pid > 1, getpgid(pid) == pid, pid != getpgrp() { run.group = pid }
        current = run
        running = true
        stopping = false
    }

    /// A read from one pipe, on the pipe's own thread. Empty means it closed.
    /// The thread waits while its bytes are decoded, so a command printing
    /// faster than that fills the pipe and waits too, and nothing piles up here.
    private func received(_ data: Data, error: Bool, run: Run) {
        queue.sync {
            guard !run.finished else { return }
            if data.isEmpty {
                // A closed pipe can report its end more than once.
                guard error ? run.errorsOpen : run.outputOpen else { return }
                (error ? run.errors : run.output).readabilityHandler = nil
                if error { run.errorsOpen = false } else { run.outputOpen = false }
                let tail = error ? run.errorDecoder.finish() : run.outputDecoder.finish()
                run.pending.append(contentsOf: tail.map { (kind: error ? .error : .output, text: $0) })
                if error { run.errorPartial = nil } else { run.outputPartial = nil }
                if !run.outputOpen, !run.errorsOpen, run.exit != nil { complete(run) }
                else { scheduleFlush(run) }
                return
            }
            // Only the last screenful survives the scrollback, so a command
            // that floods the pipe keeps no more than that waiting for it.
            let limit = NotchTerminalScrollback.defaultLimit
            if error {
                run.pending.append(contentsOf: run.errorDecoder.decode(data).suffix(limit).map { (kind: .error, text: $0) })
                run.errorPartial = run.errorDecoder.partialLine
            } else {
                run.pending.append(contentsOf: run.outputDecoder.decode(data).suffix(limit).map { (kind: .output, text: $0) })
                run.outputPartial = run.outputDecoder.partialLine
            }
            if run.pending.count > 2 * limit { run.pending.removeFirst(run.pending.count - limit) }
            scheduleFlush(run)
        }
    }

    private func exited(_ exit: NotchTerminalExit, run: Run) {
        queue.async { [weak self] in
            guard let self, !run.finished else { return }
            run.exit = exit
            if !run.outputOpen, !run.errorsOpen {
                self.complete(run)
                return
            }
            // A job left in the background keeps the pipes open; what it
            // writes after this is not the command's any more.
            self.queue.asyncAfter(deadline: .now() + Self.drainDelay) { [weak self] in
                guard let self, !run.finished else { return }
                run.leftJobs = true
                run.output.readabilityHandler = nil
                run.errors.readabilityHandler = nil
                run.pending.append(contentsOf: run.outputDecoder.finish().map { (kind: .output, text: $0) })
                run.pending.append(contentsOf: run.errorDecoder.finish().map { (kind: .error, text: $0) })
                run.outputOpen = false
                run.errorsOpen = false
                run.outputPartial = nil
                run.errorPartial = nil
                self.complete(run)
            }
        }
    }

    /// On the queue.
    private func scheduleFlush(_ run: Run) {
        guard !run.flushScheduled else { return }
        run.flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flushDelay) { [weak self] in
            self?.flush(run)
        }
    }

    /// On the queue: everything is read, so the command's last lines and its
    /// status go to the scrollback now.
    private func complete(_ run: Run) {
        run.finished = true
        DispatchQueue.main.async { [weak self] in
            self?.finish(run)
        }
    }

    private func flush(_ run: Run) {
        let batch = queue.sync { () -> (lines: [(kind: NotchTerminalLineKind, text: String)], output: String?, errors: String?) in
            run.flushScheduled = false
            defer { run.pending = [] }
            return (run.pending, run.outputPartial, run.errorPartial)
        }
        guard current === run else { return }
        if !batch.lines.isEmpty { output.scrollback.append(batch.lines) }
        var partial: [NotchTerminalLine] = []
        // Their own ids, below every line's, so a view keeps each in place.
        if let output = batch.output { partial.append(NotchTerminalLine(id: -2, kind: .output, text: output)) }
        if let errors = batch.errors { partial.append(NotchTerminalLine(id: -1, kind: .error, text: errors)) }
        if output.partialLines != partial { output.partialLines = partial }
        noteOutput()
    }

    private func finish(_ run: Run) {
        run.escalation?.cancel()
        run.escalation = nil
        // The pipes close with the process once nothing holds it.
        run.process.terminationHandler = nil
        // What the shell left running in the background hangs up with it, as
        // when a Terminal window closes, and nohup still keeps a job alive,
        // unless Stop asked for the command's end. The group outlives its
        // shell only while such a job is in it, so the number is still theirs.
        if run.leftJobs, let group = run.group { kill(-group, run.stopRequested ? SIGTERM : SIGHUP) }
        // One the page let go of while it was being ended has no scrollback left.
        guard current === run else { return }
        flush(run)
        output.partialLines = []
        if let summary = run.exit?.summary(stopped: run.stopRequested) {
            output.scrollback.append(.notice, summary)
        }
        noteOutput()
        current = nil
        running = false
        stopping = false
    }

    /// Ends a command for good, as turning the page off does: SIGTERM, then SIGKILL.
    private func terminate(_ run: Run) {
        guard run.process.isRunning else { return }
        run.stopRequested = true
        signal(run, SIGTERM)
        escalate(run, to: [SIGKILL])
    }

    private func escalate(_ run: Run, to signals: [Int32]) {
        run.escalation?.cancel()
        guard let next = signals.first else { run.escalation = nil; return }
        let work = DispatchWorkItem { [weak self, weak run] in
            guard let self, let run, run.process.isRunning else { return }
            self.signal(run, next)
            self.escalate(run, to: Array(signals.dropFirst()))
        }
        run.escalation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.escalationDelay, execute: work)
    }

    /// The shell leads a process group of its own, so the signal reaches
    /// every program in a pipeline. Only a live shell is signalled: once it is
    /// gone its number may belong to someone else.
    private func signal(_ run: Run, _ signal: Int32) {
        guard run.process.isRunning else { return }
        if let group = run.group {
            kill(-group, signal)
        } else if run.process.processIdentifier > 1 {
            kill(run.process.processIdentifier, signal)
        }
    }

    private static func kind(_ path: String) -> NotchTerminalPathKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .missing }
        guard isDirectory.boolValue else { return .notDirectory }
        return FileManager.default.isExecutableFile(atPath: path) ? .directory : .denied
    }

    /// One command's process, pipes and decoders. The decoders and what they
    /// produce belong to the queue; the rest to the main thread.
    private final class Run {
        let process: Process
        let output: FileHandle
        let errors: FileHandle
        var outputDecoder = NotchTerminalStreamDecoder()
        var errorDecoder = NotchTerminalStreamDecoder()
        var pending: [(kind: NotchTerminalLineKind, text: String)] = []
        var outputPartial: String?
        var errorPartial: String?
        var outputOpen = true
        var errorsOpen = true
        var flushScheduled = false
        var exit: NotchTerminalExit?
        var finished = false
        /// The shell's process group, which it leads; nil if it somehow doesn't.
        var group: pid_t?
        /// The shell ended with a background job still holding its pipes.
        var leftJobs = false
        var stopRequested = false
        var escalation: DispatchWorkItem?

        init(process: Process, output: FileHandle, errors: FileHandle) {
            self.process = process
            self.output = output
            self.errors = errors
        }
    }
}
