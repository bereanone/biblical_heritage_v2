import SwiftUI
import WidgetKit
import AppIntents

struct BibleRemoteEntry: TimelineEntry {
  let date: Date
  let state: WatchComplicationState
}
struct BibleRemoteProvider: TimelineProvider {
  func placeholder(in context: Context) -> BibleRemoteEntry {
    BibleRemoteEntry(date: Date(), state: .init(title: "Romans 9:11", loop: "chapter", playing: false, confirmed: true))
  }
  func getSnapshot(in context: Context, completion: @escaping (BibleRemoteEntry) -> Void) {
    completion(BibleRemoteEntry(date: Date(), state: WatchComplicationState.read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<BibleRemoteEntry>) -> Void) {
    completion(Timeline(entries: [BibleRemoteEntry(date: Date(), state: WatchComplicationState.read())], policy: .never))
  }
}
struct BibleRemoteComplicationView: View {
  let entry: BibleRemoteEntry
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "book.closed.fill")
        .font(.system(size: 26, weight: .semibold))
      VStack(alignment: .leading, spacing: 3) {
        Text("Bible Remote").font(.headline).lineLimit(1)
        Text(entry.state.title).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .accessibilityLabel("Open Bible Remote")
    .widgetURL(URL(string: "studybible-watch://remote"))
    .containerBackground(.clear, for: .widget)
  }
}
@main
struct StudyBibleRemoteWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WatchComplicationState.kind, provider: BibleRemoteProvider()) { entry in
      BibleRemoteComplicationView(entry: entry)
    }
    .configurationDisplayName("Bible Remote")
    .description("Open Bible Remote for playback and loop controls.")
    .supportedFamilies([.accessoryRectangular])
  }
}
