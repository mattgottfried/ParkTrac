//
//  TrillTrackWidgetBundle.swift
//  TrillTrackWidget
//
//  Created by Matthew R. Gottfried, CPA, MSA on 7/17/26.
//

import WidgetKit
import SwiftUI

@main
struct TrillTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrillTrackWidget()
        TrillTrackWidgetControl()
        TrillTrackWidgetLiveActivity()
    }
}
