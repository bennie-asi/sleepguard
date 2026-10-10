import SwiftUI

// SDK 27 introduces a same-name macro. Use the stable property wrapper so
// Command Line Tools builds do not require the Xcode-only macro plugin.
typealias ViewState<Value> = SwiftUI.State<Value>
