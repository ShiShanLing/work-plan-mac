//
//  WidgetReloader.swift
//  MiniTools-SwiftUI
//

import Foundation
import WidgetKit

enum MiniToolsWidgetReloader {
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
