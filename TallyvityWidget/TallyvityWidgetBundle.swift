//
//  TallyvityWidgetBundle.swift
//  TallyvityWidget
//
//  Created by Elia Salerno on 21.04.2026.
//

import WidgetKit
import SwiftUI

@main
struct DexarWidgetBundle: WidgetBundle {
    var body: some Widget {
        DexarWidget()
        DexarWidgetControl()
        DexarWidgetLiveActivity()
    }
}
