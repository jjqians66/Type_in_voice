import AppKit
import ApplicationServices
import CoreGraphics

/// Inserts transcribed text into the app captured at recording start by
/// setting the pasteboard and simulating ⌘V.
class TextInserter {

    /// Insert text into the captured target app.
    /// Returns false when Accessibility or a safe target app is unavailable.
    @discardableResult
    func insertText(_ text: String, targetProcessID: pid_t?) -> Bool {
        let pasteboard = NSPasteboard.general

        // Always set the clipboard first — even if paste simulation fails,
        // the user can manually ⌘V.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("Type in Voice: set clipboard with \(text.count) chars")

        guard AXIsProcessTrusted() else {
            print("Type in Voice: accessibility permission is not granted")
            return false
        }

        guard let targetPID = targetProcessID,
              NSRunningApplication(processIdentifier: targetPID) != nil,
              targetPID != ProcessInfo.processInfo.processIdentifier else {
            print("Type in Voice: no safe target app; text remains on clipboard")
            return false
        }

        // Small delay to ensure pasteboard is ready, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.simulatePaste(to: targetPID)
        }

        return true
    }

    // MARK: - Private

    private func simulatePaste(to pid: pid_t) {
        guard NSRunningApplication(processIdentifier: pid) != nil else {
            print("Type in Voice: target app is no longer running; text remains on clipboard")
            return
        }

        print("Type in Voice: pasting to target pid=\(pid)")

        // Create ⌘V key down event
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code 9 = V key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            print("Type in Voice: failed to create paste event")
            return
        }

        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post directly to the app that had focus when recording started.
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        print("Type in Voice: sent ⌘V to pid=\(pid)")
    }
}
