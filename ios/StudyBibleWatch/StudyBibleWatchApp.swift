import SwiftUI
import WatchConnectivity

@main
struct StudyBibleWatchApp: App {
  @StateObject private var remote = BibleWatchSession.shared

  var body: some Scene {
    WindowGroup {
      WatchRemoteView().environmentObject(remote)
    }
  }
}

private struct WatchRemoteView: View {
  @EnvironmentObject private var remote: BibleWatchSession
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.isLuminanceReduced) private var isLuminanceReduced
  @State private var choosingLibrary = false
  @FocusState private var controlsFocused: Bool
  @State private var choosingBook = false
  @State private var selectedBook = 1
  @State private var pickerUnit = "book"

  var body: some View {
    Group {
      if isLuminanceReduced {
        VStack(spacing: 8) {
          Text(remote.title).font(.headline).multilineTextAlignment(.center)
          Text("\(remote.mode == "library" ? "eLibrary" : "Bible") · \(remote.playing ? "Playing" : "Paused")")
            .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
      } else {
        controls
      }
    }
    .onAppear { updateDisplayActivity(); controlsFocused = !isLuminanceReduced }
    .onDisappear { remote.setForeground(false) }
    .onChange(of: scenePhase) { _, _ in updateDisplayActivity() }
    .onChange(of: isLuminanceReduced) { _, _ in updateDisplayActivity() }
  }

  private func updateDisplayActivity() {
    remote.setForeground(scenePhase == .active && !isLuminanceReduced)
  }

  private var controls: some View {
    ScrollView {
      VStack(spacing: 9) {
        Text(remote.title).font(.headline).multilineTextAlignment(.center)
        Text("\(remote.mode == "library" ? "eLibrary" : "Bible") · " + (remote.loop == "off" ? "Loop off" : "Loop: \(remote.loop == "verse" && remote.mode == "library" ? "Paragraph" : remote.loop.capitalized)"))
          .font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Button {
            remote.command(remote.confirmed && remote.playing ? "stop" : "start")
          } label: {
            Text(remote.confirmed && remote.playing ? "Stop" : "Start")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          Button { remote.command(remote.mode == "bible" ? "mode:library" : "mode:bible") } label: {
            Text(remote.mode == "library" ? "eLibrary ⇄" : "Bible ⇄").frame(maxWidth:.infinity)
          }
          .disabled(remote.awaitingReply)
          .accessibilityLabel("Switch Bible or eLibrary")
          .accessibilityValue(remote.mode == "library" ? "eLibrary" : "Bible")
          .buttonStyle(.bordered)
        }
        HStack(spacing: 8) {
          Button { remote.command("previous:\(remote.draftLoopUnit)") } label: {
            Text("Previous").frame(maxWidth: .infinity)
          }
          .accessibilityLabel("Previous \(remote.skipUnit)")
          Button { remote.command("next:\(remote.draftLoopUnit)") } label: {
            Text("Next").frame(maxWidth: .infinity)
          }
          .accessibilityLabel("Next \(remote.skipUnit)")
        }
        .buttonStyle(.bordered)
        Divider()
        Text("Choose loop").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 4) {
          loopUnitButton("Book", unit: "book")
          loopUnitButton("Chapter", unit: "chapter")
          loopUnitButton(remote.mode == "library" ? "Paragraph" : "Verse", unit: "verse")
        }
        Text("Selected: \(remote.skipUnit.capitalized)").font(.caption).fontWeight(.bold)
        HStack(spacing: 8) {
          Button { remote.command("loop:\(remote.draftLoopUnit)") } label: {
            Text("Engage").frame(maxWidth: .infinity)
          }
          .disabled(remote.awaitingReply || remote.loop == remote.draftLoopUnit)
          Button { remote.command("loop:off") } label: {
            Text("Off").frame(maxWidth: .infinity)
          }
          .disabled(remote.awaitingReply || remote.loop == "off")
        }
        .buttonStyle(.bordered)
        Button {
          if remote.mode == "library" {
            pickerUnit = remote.draftLoopUnit
            choosingLibrary = true
            return
          }
          pickerUnit = remote.draftLoopUnit
          selectedBook = pickerUnit == "book" ? remote.bookNumber : (pickerUnit == "chapter" ? remote.chapterNumber : remote.verseNumber)
          controlsFocused = false
          choosingBook = true
        } label: {
          Label(remote.mode == "library" && remote.draftLoopUnit == "book" ? "Choose book / contents" : "Choose \(remote.skipUnit)", systemImage: "book.closed").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered).disabled(remote.awaitingReply)
        if let message = remote.message {
          Text(message).font(.caption2).multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 6)
    }
    .focusable()
    .focused($controlsFocused)
    .sheet(isPresented: $choosingBook, onDismiss: { controlsFocused = true }) {
      VStack {
        Picker(pickerUnit.capitalized, selection: $selectedBook) {
          if pickerUnit == "book" {
            ForEach(Array(Self.books.enumerated()), id: \.offset) { index, name in
              Text(name).tag(index + 1)
            }
          } else {
            ForEach(1...(pickerUnit == "chapter" ? remote.chapterCount : remote.verseCount), id: \.self) { number in
              Text("\(pickerUnit.capitalized) \(number)").tag(number)
            }
          }
        }.pickerStyle(.wheel)
        Button("Go to \(pickerUnit)") {
          remote.command("\(pickerUnit):\(selectedBook)")
          choosingBook = false
        }.buttonStyle(.borderedProminent)
      }
    }
    .sheet(isPresented:$choosingLibrary) {
      NavigationStack {
        if pickerUnit == "verse", !remote.libraryBookID.isEmpty {
          List(remote.libraryParagraphs) { entry in
            Button(entry.title) {
              remote.command("libraryLocation:\(entry.chapter):\(entry.paragraph)")
              choosingLibrary = false
            }.disabled(remote.awaitingReply)
          }.navigationTitle("Paragraphs")
        } else if pickerUnit == "chapter", !remote.libraryBookID.isEmpty {
          WatchAudioContentsView(bookID:remote.libraryBookID,close:{choosingLibrary = false})
        } else {
          List {
            if remote.libraryBooks.isEmpty {
              Text("No Top Shelf books have downloaded audio. Open eLibrary on iPhone to refresh.").font(.caption)
            }
            ForEach(remote.libraryBooks) { book in
              NavigationLink(book.title) {
                WatchAudioContentsView(bookID:book.id,close:{choosingLibrary = false})
              }.disabled(remote.awaitingReply)
            }
          }.navigationTitle("Top Shelf Audio")
        }
      }.environmentObject(remote)
    }
  }

  private static let books = ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi", "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation"]

  private func loopUnitButton(_ label: String, unit: String) -> some View {
    Button { remote.selectLoopUnit(unit) } label: {
      HStack(spacing: 2) {
        if remote.draftLoopUnit == unit { Image(systemName: "checkmark") }
        Text(label).lineLimit(1).minimumScaleFactor(0.6)
      }.font(.caption2)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.mini)
    .tint(remote.draftLoopUnit == unit ? .yellow : Color.gray.opacity(0.25))
    .foregroundStyle(remote.draftLoopUnit == unit ? .black : .white)
    .disabled(remote.awaitingReply)
    .accessibilityLabel("Loop \(label)")
    .accessibilityValue(remote.draftLoopUnit == unit ? "Selected" : "Not selected")
  }
}

private struct WatchAudioContentsView: View {
  @EnvironmentObject private var remote:BibleWatchSession
  let bookID:String
  let close:()->Void
  var body:some View {
    Group {
      if remote.libraryBookID != bookID || remote.awaitingReply {
        ProgressView("Loading contents…")
      } else {
        List(remote.libraryTOC) { entry in
          Button(entry.title) {
            remote.command("libraryLocation:\(entry.chapter):\(entry.paragraph)")
            close()
          }.disabled(remote.awaitingReply)
        }
      }
    }
    .navigationTitle("Contents")
    .task(id:bookID) {
      if remote.libraryBookID != bookID { try? await remote.execute("libraryBook:"+bookID) }
    }
  }
}
