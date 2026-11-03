// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import AppKit
import SwiftUI

/// The island's terminal: the scrollback fills the page and the prompt, with
/// the current folder, sits under it. Return runs the line in the login
/// shell, Up and Down walk back through earlier commands, Control-C stops the
/// one running and Control-L clears; Escape still closes the island, as on
/// every page. The top row holds Stop while a command runs, Clear and Open in
/// Terminal.
struct NotchTerminalView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var terminal = NotchTerminalService.shared
    @State private var input = ""
    @FocusState private var focused: Bool
    @Environment(\.notchSettingsPreview) private var preview
    private static let font = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(spacing: 6) {
            NotchTerminalOutputList(output: terminal.output, running: terminal.running)
            prompt
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .notchBand(trailing: {
            HStack(spacing: 6) {
                if terminal.running {
                    NotchIconButton(symbol: "stop.fill", title: NotchTerminalText.stop, action: terminal.interrupt)
                        .disabled(terminal.stopping)
                }
                NotchIconButton(symbol: "eraser", title: NotchTerminalText.clear, action: terminal.clear)
                    .disabled(!terminal.hasOutput)
                NotchIconButton(symbol: "apple.terminal", title: NotchTerminalText.openInTerminal,
                                action: terminal.openInTerminal)
            }
        })
        .background {
            if !preview {
                NotchTerminalKeyMonitor(handleKey: handleKey)
                    .frame(width: 0, height: 0)
            }
        }
        .onAppear {
            input = terminal.draft
            if !preview { focused = true }
        }
        .onDisappear {
            if !preview { terminal.draft = input }
        }
        // Opened by hover, the island takes the keyboard on the first click;
        // the prompt has it from then on, wherever the click was.
        .onChange(of: service.panelIsKey) { _, isKey in
            if isKey, !preview { focused = true }
        }
    }

    private var prompt: some View {
        HStack(spacing: 6) {
            Text(terminal.displayDirectory)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: max(60, size.width * 0.4), alignment: .leading)
                .layoutPriority(1)
                .help(terminal.directory)
            Text(terminal.promptSymbol)
                .foregroundStyle(.white.opacity(0.55))
                .accessibilityHidden(true)
            TextField(NotchTerminalText.placeholder, text: $input)
                .textFieldStyle(.plain)
                .focused($focused)
                .disabled(preview)
                .onSubmit(submit)
                .accessibilityLabel(NotchTerminalText.placeholder)
        }
        .font(Self.font)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .modifier(NotchControlSurface(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.3 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    /// The line stays at the prompt while a command runs, ready to go once it ends.
    private func submit() {
        guard !terminal.running else {
            NSSound.beep()
            return
        }
        let line = input
        input = ""
        terminal.submit(line)
    }

    private func handleKey(_ key: NotchTerminalKey) -> Bool {
        switch key {
        case .older:
            if let older = terminal.olderCommand(than: input) { input = older }
        case .newer:
            if let newer = terminal.newerCommand() { input = newer }
        case .submit:
            submit()
        case .interrupt:
            // At an idle prompt Control-C drops the line, as the shell does.
            if terminal.running { terminal.interrupt() } else { input = "" }
        case .clear:
            terminal.clear()
        }
        return true
    }
}

/// The scrollback and the lines still being written, observed here alone: a
/// command that prints fast redraws this list and leaves the island's top row
/// and the prompt as they are.
private struct NotchTerminalOutputList: View {
    @ObservedObject var output: NotchTerminalOutput
    let running: Bool
    private static let endID = -1_000

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(output.scrollback.lines) { row($0) }
                    ForEach(output.partialLines) { row($0) }
                    Color.clear.frame(height: 1).id(Self.endID)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .overlay {
                if output.isEmpty, !running {
                    Text(NotchTerminalText.emptyHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            // The newest output stays in view, as in Terminal.
            .onAppear { proxy.scrollTo(Self.endID, anchor: .bottom) }
            .onChange(of: output.scrollback.nextID) { _, _ in proxy.scrollTo(Self.endID, anchor: .bottom) }
            .onChange(of: output.partialLines) { _, _ in proxy.scrollTo(Self.endID, anchor: .bottom) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
    }

    private func row(_ line: NotchTerminalLine) -> some View {
        Text(line.text.isEmpty ? " " : line.text)
            .font(.system(size: 11, design: .monospaced))
            .fontWeight(line.kind == .command ? .semibold : .regular)
            .foregroundStyle(Self.color(line.kind))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private static func color(_ kind: NotchTerminalLineKind) -> Color {
        switch kind {
        case .command: return .white
        case .output: return .white.opacity(0.82)
        case .error: return Color(red: 1, green: 0.56, blue: 0.52)
        case .notice: return Color(red: 0.98, green: 0.78, blue: 0.42)
        }
    }
}

/// Reads the prompt's keys before its field does, while the field has the
/// keyboard and no input method is composing; any other key goes on to it.
private struct NotchTerminalKeyMonitor: NSViewRepresentable {
    var handleKey: (NotchTerminalKey) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handleKey = handleKey
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(handleKey: handleKey)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var handleKey: (NotchTerminalKey) -> Bool
        private var monitor: Any?

        init(handleKey: @escaping (NotchTerminalKey) -> Bool) {
            self.handleKey = handleKey
        }

        func install(for view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let window = view?.window, event.window === window,
                      let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                      !editor.hasMarkedText() else { return event }
                let modifiers = event.modifierFlags
                guard let key = NotchTerminalKey(keyCode: event.keyCode,
                                                 characters: event.charactersIgnoringModifiers ?? "",
                                                 command: modifiers.contains(.command),
                                                 control: modifiers.contains(.control),
                                                 option: modifiers.contains(.option),
                                                 shift: modifiers.contains(.shift)) else { return event }
                return self.handleKey(key) ? nil : event
            }
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
