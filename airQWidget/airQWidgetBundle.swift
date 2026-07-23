//
//  airQWidgetBundle.swift
//  airQWidget
//
//  Created by Mahil Manoharan on 7/18/26.
//

import WidgetKit
import SwiftUI

@main
struct airQWidgetBundle: WidgetBundle {
    var body: some Widget {
        AQIWidget()
        PollenWidget()
        CombinedWidget()
    }
}
