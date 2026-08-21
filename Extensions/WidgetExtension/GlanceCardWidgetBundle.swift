import LockTodoNoteShared
import SwiftUI
import WidgetKit

@main
struct GlanceCardWidgetBundle: WidgetBundle {
  var body: some Widget {
    GlanceCardLockScreenWidget()
    if #available(iOSApplicationExtension 16.1, *) {
      GlanceCardLiveActivity()
    }
  }
}
