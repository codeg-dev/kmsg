import ApplicationServices
import Foundation

/// Replaces bodies of bubbles truncated with "…" by the full text from KakaoTalk's see-all dialog.
/// Only the target chat window's transcript buttons are pressed, and every dialog it opens is closed again.
struct SeeAllExpander {
    let kakao: KakaoTalkApp

    func expand(_ snapshot: TranscriptSnapshot, in window: UIElement) -> TranscriptSnapshot {
        let wanted = Set(snapshot.messages.filter { $0.body.hasSuffix("…") }.map { squash($0.body) })
        guard !wanted.isEmpty else { return snapshot }
        var full: [String: String] = [:]
        for (key, button) in truncatedBubbles(in: window) where wanted.contains(key) && full[key] == nil {
            if let text = readDialog(pressing: button) { full[key] = text }
        }
        let messages = snapshot.messages.map { m -> TranscriptMessage in
            guard let text = full[squash(m.body)] else { return m }
            return TranscriptMessage(
                author: m.author, timeRaw: m.timeRaw, body: text,
                imageCount: m.imageCount, linkCount: m.linkCount, attachmentCount: m.attachmentCount,
                isSystem: m.isSystem, logicalTimestamp: m.logicalTimestamp, date: m.date
            )
        }
        return TranscriptSnapshot(chat: snapshot.chat, fetchedAt: snapshot.fetchedAt, messages: messages)
    }

    private func squash(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    private func truncatedBubbles(in window: UIElement) -> [(String, UIElement)] {
        let tables = window.children
            .filter { $0.role == kAXScrollAreaRole }
            .flatMap { $0.children.filter { $0.role == kAXTableRole } }
        var result: [(String, UIElement)] = []
        for row in tables.flatMap(\.children) {
            for cell in row.children {
                let items = cell.children
                guard let text = items.first(where: { $0.role == kAXTextAreaRole && ($0.stringValue ?? "").hasSuffix("…") }),
                      let textFrame = text.frame,
                      let button = items.last(where: { $0.role == kAXButtonRole && ($0.title ?? "").isEmpty && ($0.axDescription ?? "").isEmpty }),
                      let buttonFrame = button.frame, buttonFrame.minY >= textFrame.maxY - 2
                else { continue }
                result.append((squash(text.stringValue ?? ""), button))
            }
        }
        return result
    }

    private func readDialog(pressing button: UIElement) -> String? {
        let before = kakao.windows
        try? button.press()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let dialog = kakao.windows.first(where: { candidate in
                let subrole: String? = candidate.attributeOptional(kAXSubroleAttribute)
                return subrole == "AXDialog" && !before.contains { CFEqual($0.axElement, candidate.axElement) }
            }) {
                let text = longestValue(in: dialog, depth: 0)
                if let close: AXUIElement = dialog.attributeOptional(kAXCloseButtonAttribute) {
                    try? UIElement(close).press()
                }
                return text.isEmpty ? nil : text
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private func longestValue(in element: UIElement, depth: Int) -> String {
        var best = element.stringValue ?? ""
        guard depth < 10 else { return best }
        for child in element.children {
            let candidate = longestValue(in: child, depth: depth + 1)
            if candidate.count > best.count { best = candidate }
        }
        return best
    }
}
