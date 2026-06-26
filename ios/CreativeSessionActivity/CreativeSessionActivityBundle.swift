import SwiftUI
import WidgetKit

@main
struct CreativeSessionActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOSApplicationExtension 16.1, *) {
            CreativeSessionActivityWidget()
        }
    }
}
