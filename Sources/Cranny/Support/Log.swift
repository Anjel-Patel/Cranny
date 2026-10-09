import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "io.github.rdbms234.Cranny", category: "app")
    static let media = Logger(subsystem: "io.github.rdbms234.Cranny", category: "media")
    static let tray = Logger(subsystem: "io.github.rdbms234.Cranny", category: "tray")
    static let calendar = Logger(subsystem: "io.github.rdbms234.Cranny", category: "calendar")
}

import SwiftUI

/// SwiftUI's `@State` is a compiler macro in the macOS 27 SDK, and its plugin only ships
/// with full Xcode. Using the property wrapper through an alias keeps the project
/// buildable with just the Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
