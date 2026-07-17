//
//  TrillTrackWidgetLiveActivity.swift
//  TrillTrackWidget
//
//  Created by Matthew R. Gottfried, CPA, MSA on 7/17/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TrillTrackWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct TrillTrackWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrillTrackWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension TrillTrackWidgetAttributes {
    fileprivate static var preview: TrillTrackWidgetAttributes {
        TrillTrackWidgetAttributes(name: "World")
    }
}

extension TrillTrackWidgetAttributes.ContentState {
    fileprivate static var smiley: TrillTrackWidgetAttributes.ContentState {
        TrillTrackWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: TrillTrackWidgetAttributes.ContentState {
         TrillTrackWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: TrillTrackWidgetAttributes.preview) {
   TrillTrackWidgetLiveActivity()
} contentStates: {
    TrillTrackWidgetAttributes.ContentState.smiley
    TrillTrackWidgetAttributes.ContentState.starEyes
}
