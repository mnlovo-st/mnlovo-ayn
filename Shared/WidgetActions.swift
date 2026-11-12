import AppIntents
import WidgetKit
import ActivityKit

/// The ✓ button on the widgets.
///
/// It's a `LiveActivityIntent` on purpose: intents of that kind run inside the app's own process
/// (iOS wakes it in the background for a moment), and the app is the only one holding the key to
/// the reminders. The widget-side copy of this file (compiled with SAVER_WIDGET) can't open the
/// vault, so there the tap is shown at once and queued; the app applies the queue the next time it
/// runs. Either way the tick sticks.
struct CompleteFromWidgetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark as done"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Reminder") var reminderID: String
    @Parameter(title: "Routine") var isRoutine: Bool

    init() {}
    init(id: String, routine: Bool) {
        reminderID = id
        isRoutine = routine
    }

    func perform() async throws -> some IntentResult {
        WidgetShared.tickLocally(id: reminderID, routine: isRoutine)
        #if !SAVER_WIDGET
        await MainActor.run {
            WidgetQueue.drain()
            WidgetBridge.updateNow()
        }
        #endif
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
