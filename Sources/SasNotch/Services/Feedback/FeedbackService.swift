// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified for SasNotch by SasNotch contributors, 2026

import AppKit
import Foundation

enum FeedbackKind: String, Codable, CaseIterable {
    case bug
    case feature
}

struct FeedbackDiagnostics: Codable {
    let appVersion: String
    let appBuild: String
    let macOS: String
    let macModel: String?
    let language: String
    let isBeta: Bool
    let updateChannel: String

    static func current() -> FeedbackDiagnostics {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let isBeta = AppInfo.isBeta
        let channel = AppInfo.isDeveloperBuild ? "developer" : (isBeta ? "beta" : (UpdateService.shared.includeBetaUpdates ? "beta-opt-in" : "stable"))
        return FeedbackDiagnostics(
            appVersion: AppInfo.version,
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            macModel: modelIdentifier,
            language: L10n.shared.language.rawValue,
            isBeta: isBeta,
            updateChannel: channel
        )
    }

    private static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }()
}

private struct FeedbackSubmission: Codable {
    let kind: FeedbackKind
    let message: String
    let diagnostics: FeedbackDiagnostics?
}

enum FeedbackError: Error {
    case unavailable
    case rateLimited
    case rejected
    case invalidResponse
}

/// Feedback goes to the project's GitHub issues. SasNotch runs no server, so
/// nothing is sent from the app: it opens a new issue in the browser with the
/// message and, when chosen, the diagnostics filled in, and the person
/// submits it there.
@MainActor
final class FeedbackService {
    static let shared = FeedbackService()

    private init() {}

    func submit(kind: FeedbackKind,
                message: String,
                diagnostics: FeedbackDiagnostics?) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count >= 10, trimmed.utf16.count <= 2_000 else {
            throw FeedbackError.rejected
        }
        guard let url = Self.issueURL(kind: kind, message: trimmed, diagnostics: diagnostics),
              NSWorkspace.shared.open(url) else {
            throw FeedbackError.unavailable
        }
    }

    static func issueURL(kind: FeedbackKind, message: String, diagnostics: FeedbackDiagnostics?) -> URL? {
        let firstLine = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
        let title = firstLine.count > 80 ? String(firstLine.prefix(77)) + "…" : firstLine
        var body = message
        if let diagnostics {
            body += """


            ---
            SasNotch \(diagnostics.appVersion) (\(diagnostics.appBuild))
            macOS \(diagnostics.macOS)\(diagnostics.macModel.map { " · \($0)" } ?? "")
            Language: \(diagnostics.language) · Channel: \(diagnostics.updateChannel)
            """
        }
        var components = URLComponents(url: AppInfo.issuesURL.appendingPathComponent("new"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: kind == .bug ? "bug" : "enhancement"),
        ]
        return components?.url
    }
}

