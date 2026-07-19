import WidgetKit
import SwiftUI

@main
struct TrillTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrillTrackWidgetLiveActivity()
        WaitTimeWidget()
    }
}
