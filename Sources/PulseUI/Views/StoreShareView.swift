// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import CoreData
import Pulse
import Combine

#if os(iOS) || os(macOS)

@available(iOS 14, tvOS 14, *)
struct ShareStoreView: View {
    let store: LoggerStore

    @StateObject private var viewModel = ShareStoreViewModel()
    @State private var shareItem: ShareItems?
    @Binding var isPresented: Bool // presentationMode is buggy

#if os(macOS)
    let onShare: (ShareItems) -> Void
#endif

    var body: some View {
        Form {
            sectionSharingOptions
            sectionStatus
            sectionShare
        }
        .onAppear { viewModel.display(store) }
        .navigationTitle("Sharing Options")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(leading: leadingBarItems)
#endif
        .sheet(item: $shareItem) {
            ShareView($0).onCompletion {
                isPresented = false
            }
        }
#if os(macOS)
        .padding()
#endif
    }

    private var leadingBarItems: some View {
        Button("Cancel") {
            isPresented = false
        }
    }

    private var sectionSharingOptions: some View {
        Section {
            Picker("Time Range", selection: $viewModel.timeRange) {
                ForEach(SharingTimeRange.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            Picker("Minimum Log Level", selection: $viewModel.level) {
                Text("Trace").tag(LoggerStore.Level.trace)
                Text("Debug").tag(LoggerStore.Level.debug)
                Text("Error").tag(LoggerStore.Level.error)
            }
            Picker("Output Format", selection: $viewModel.output) {
                Text("File (.pulse)")
                    .lineLimit(1)
                    .tag(ShareStoreOutput.store)
                Text("Text (.txt)")
                    .lineLimit(1)
                    .tag(ShareStoreOutput.text)
            }
        }
    }

    private var sectionStatus: some View {
        Section {
            if viewModel.isPreparingForSharing {
                HStack(spacing: 8) {
#if os(iOS)
                    ProgressView().id(UUID())
#endif
                    Text("Preparing for Sharing...")
                        .foregroundColor(.secondary)
                }
            } else if let contents = viewModel.sharedContents {
                if let info = contents.info {
#if os(iOS)
                    NavigationLink(destination: StoreDetailsView(source: .info(info))) {
                        InfoRow(title: "Shared File Size", details: contents.formattedFileSize)
                    }
#else
                    InfoRow(title: "Shared File Size", details: contents.formattedFileSize)
#endif
                } else {
                    InfoRow(title: "Shared File Size", details: contents.formattedFileSize)
                }
            } else {
                Text(viewModel.errorMessage ?? "Unavailable")
                    .foregroundColor(.red)
                    .lineLimit(3)
            }
        }
    }

    private var sectionShare: some View {
        Section {
            Button(action: buttonShareTapped) {
                HStack {
                    Spacer()
                    Text("Share").bold()
                    Spacer()
                }
            }
            .disabled(viewModel.sharedContents == nil)
            .foregroundColor(.white)
            .listRowBackground(viewModel.sharedContents != nil ? Color.blue : Color.blue.opacity(0.33))
        }
    }

    private func buttonShareTapped() {
        guard let item = viewModel.sharedContents?.item else { return }
#if os(macOS)
        onShare(item)
#else
        self.shareItem = item
#endif
    }
}

private final class ShareStoreViewModel: ObservableObject {
    // Sharing options
    @Published var timeRange: SharingTimeRange
    @Published var level: LoggerStore.Level
    @Published var output: ShareStoreOutput

    // Settings
    @Published private(set) var isPreparingForSharing = false
    @Published private(set) var sharedContents: SharedContents?
    @Published private(set) var errorMessage: String?

    private var store: LoggerStore?
    private var isPrepareForSharingNeeded = false
    private var cancellable: AnyCancellable?

    init() {
        timeRange = ConsoleSettings.shared.sharingTimeRange
        level = ConsoleSettings.shared.sharingLevel
        output = ConsoleSettings.shared.sharingOutput
    }

    func display(_ store: LoggerStore) {
        guard self.store !== store else {
            return
        }

        self.store = store

        if cancellable == nil {
            cancellable = Publishers.CombineLatest3($timeRange, $output, $level)
                .dropFirst()
                .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] _, _, _ in
                    self?.saveSharingOptions()
                    self?.setNeedsPrepareForSharing()
                }
        }

        self.prepareForSharing()
    }

    private func setNeedsPrepareForSharing() {
        if isPreparingForSharing {
            isPrepareForSharingNeeded = true
        } else {
            prepareForSharing()
        }
    }

    private func saveSharingOptions() {
        ConsoleSettings.shared.sharingTimeRange = timeRange
        ConsoleSettings.shared.sharingLevel = level
        ConsoleSettings.shared.sharingOutput = output
    }

    func prepareForSharing() {
        guard let store = store else { return }

        isPreparingForSharing = true
        sharedContents = nil
        errorMessage = nil

        let context = store.backgroundContext
        let predicate = self.predicate
        context.perform {
            self.prepareForSharing(store: store, context: context, predicate: predicate)
        }
    }

    private var predicate: NSPredicate? {
        if timeRange == .all && level == .trace {
            return nil
        }
        var predicates: [NSPredicate] = []
        switch timeRange {
        case .currentSession:
            predicates.append(.init(format: "session == %@",  LoggerStore.Session.current.id as NSUUID))
        case .lastHour:
            predicates.append(.init(format: "createdAt >= %@", Date().addingTimeInterval(-3600) as NSDate))
        case .today:
            let cutoffDate = Calendar.current.startOfDay(for: Date())
            predicates.append(.init(format: "createdAt >= %@", cutoffDate as NSDate))
        case .all:
            break
        }
        if level != .trace {
            predicates.append(.init(format: "level >= %i", level.rawValue))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func prepareForSharing(store: LoggerStore, context: NSManagedObjectContext, predicate: NSPredicate?) {
        let directory = TemporaryDirectory()
        do {
            let contents = try prepareForSharing(store: store, context: context, directory: directory, predicate: predicate)
            DispatchQueue.main.async {
                self.sharedContents = contents
                self.didFinishPreparingForSharing()
            }
        } catch {
            directory.remove()
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.didFinishPreparingForSharing()
            }
        }
    }

    private func didFinishPreparingForSharing() {
        if isPrepareForSharingNeeded {
            isPrepareForSharingNeeded = false
            prepareForSharing()
        } else {
            isPreparingForSharing = false
        }
    }

    private func prepareForSharing(store: LoggerStore, context: NSManagedObjectContext, directory: TemporaryDirectory, predicate: NSPredicate?) throws -> SharedContents {
        let logsURL: URL
        var info: LoggerStore.Info?
        switch output {
        case .store:
            logsURL = directory.url.appendingPathComponent("logs-\(makeCurrentDate()).pulse")
            if let predicate = predicate {
                info = try store.copy(to: logsURL, predicate: predicate)
            } else {
                info = try store.copy(to: logsURL)
            }
        case .text:
            let request = NSFetchRequest<LoggerMessageEntity>(entityName: "\(LoggerMessageEntity.self)")
            request.predicate = predicate
            let messages: [LoggerMessageEntity] = try context.fetch(request)
            let renderer = TextRenderer(options: .sharing)
            let text = renderer.joined(messages.map {
                if let task = $0.task {
                    return renderer.render(task, content: .sharing)
                } else {
                    return renderer.render($0)
                }
            }).string
            logsURL = directory.url.appendingPathComponent("logs-\(makeCurrentDate()).txt")
            try text.data(using: .utf8)?.write(to: logsURL)
        }
        let item = ShareItems([logsURL], cleanup: directory.remove)
        return SharedContents(item: item, size: try logsURL.getFileSize(), info: info)
    }
}

private extension URL {
    func getFileSize() throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return attributes[.size] as? Int64 ?? 0
    }
}

private struct SharedContents {
    var item: ShareItems?
    var size: Int64 = 0
    var info: LoggerStore.Info?

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: size)
    }
}

#if DEBUG
@available(iOS 14, tvOS 14, *)
struct ShareStoreView_Previews: PreviewProvider {
    static var previews: some View {
#if os(iOS)
        NavigationView {
            ShareStoreView(store: .mock, isPresented: .constant(true))
        }
#else
        ShareStoreView(store: .mock, isPresented: .constant(true), onShare: { _ in })
            .frame(width: 300, height: 500)
#endif
    }
}
#endif

#endif

enum SharingTimeRange: String, CaseIterable, RawRepresentable {
    case currentSession = "This Session"
    case lastHour = "Last Hour"
    case today = "Today"
    case all = "All Messages"
}
