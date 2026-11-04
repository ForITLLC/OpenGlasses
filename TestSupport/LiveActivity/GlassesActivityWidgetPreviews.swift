#if DEBUG
import ActivityKit
import SwiftUI
import WidgetKit

// These macros instantiate the production Widget, including its real intent.
// Each preview offers six content states. Use canvas appearance/dynamic-type
// settings for light/dark and Large/accessibility5; the host owns these traits.
// A canvas capture is preparation, never system-hosted screenshot acceptance.
#Preview("Glasses • Lock Screen", as: .content,
         using: GlassesActivityFixtures.attributes) {
    GlassesActivityWidget()
} contentStates: {
    GlassesActivityFixtures.disconnected.state
    GlassesActivityFixtures.ready.state
    GlassesActivityFixtures.listening.state
    GlassesActivityFixtures.processing.state
    GlassesActivityFixtures.speaking.state
    GlassesActivityFixtures.longContent.state
}

#Preview("Glasses • Island expanded", as: .dynamicIsland(.expanded),
         using: GlassesActivityFixtures.attributes) {
    GlassesActivityWidget()
} contentStates: {
    GlassesActivityFixtures.disconnected.state
    GlassesActivityFixtures.ready.state
    GlassesActivityFixtures.listening.state
    GlassesActivityFixtures.processing.state
    GlassesActivityFixtures.speaking.state
    GlassesActivityFixtures.longContent.state
}

#Preview("Glasses • Island compact", as: .dynamicIsland(.compact),
         using: GlassesActivityFixtures.attributes) {
    GlassesActivityWidget()
} contentStates: {
    GlassesActivityFixtures.disconnected.state
    GlassesActivityFixtures.ready.state
    GlassesActivityFixtures.listening.state
    GlassesActivityFixtures.processing.state
    GlassesActivityFixtures.speaking.state
    GlassesActivityFixtures.longContent.state
}

#Preview("Glasses • Island minimal", as: .dynamicIsland(.minimal),
         using: GlassesActivityFixtures.attributes) {
    GlassesActivityWidget()
} contentStates: {
    GlassesActivityFixtures.disconnected.state
    GlassesActivityFixtures.ready.state
    GlassesActivityFixtures.listening.state
    GlassesActivityFixtures.processing.state
    GlassesActivityFixtures.speaking.state
    GlassesActivityFixtures.longContent.state
}
#endif
