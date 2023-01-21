// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import CoreData
import Pulse
import Combine

#if os(iOS)

import UniformTypeIdentifiers

struct ConsoleContextMenu: View {
    @ObservedObject var viewModel: ConsoleViewModel
    @Binding var isShowingAsText: Bool

    @State private var isShowingSettings = false
    @State private var isShowingStoreInfo = false
    @State private var isShowingInsights = false
    @State private var isShowingShareStore = false
    @State private var isDocumentBrowserPresented = false

    var body: some View {
        Menu {
            Section {
                Button(action: { isShowingAsText.toggle() }) {
                    if isShowingAsText {
                        Label("View as List", systemImage: "list.bullet.rectangle.portrait")
                    } else {
                        Label("View as Text", systemImage: "text.quote")
                    }
                }
                if !viewModel.store.isArchive {
                    Button(action: { isShowingInsights = true }) {
                        Label("Insights", systemImage: "chart.pie")
                    }
                }
            }
            Section {
                Button(action: { isShowingStoreInfo = true }) {
                    Label("Store Info", systemImage: "info.circle")
                }
                Button(action: { isShowingShareStore = true }) {
                    Label("Share Store", systemImage: "square.and.arrow.up")
                }
                if !viewModel.store.isArchive {
                    Button.destructive(action: buttonRemoveAllTapped) {
                        Label("Remove Logs", systemImage: "trash")
                    }
                }
            }
            Section {
                if viewModel.order == .latestFirst {
                    Button(action: { viewModel.order = .oldestFirst }) {
                        Label("Newest First", systemImage: "arrow.down")
                    }
                } else {
                    Button(action: { viewModel.order = .latestFirst }) {
                        Label("Oldest First", systemImage: "arrow.up")
                    }
                }
                Button(action: { isShowingSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
            }
            Section {
                if !UserDefaults.standard.bool(forKey: "pulse-disable-support-prompts") {
                    Button(action: buttonSponsorTapped) {
                        Label("Sponsor", systemImage: "heart")
                    }
                }
                Button(action: buttonSendFeedbackTapped) {
                    Label("Report Issue", systemImage: "envelope")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationView {
                SettingsView(store: viewModel.store)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(trailing: Button(action: { isShowingSettings = false }) {
                        Text("Done")
                    })
            }
        }
        .sheet(isPresented: $isShowingStoreInfo) {
            NavigationView {
                StoreDetailsView(source: .store(viewModel.store))
                    .navigationBarItems(trailing: Button(action: { isShowingStoreInfo = false }) {
                        Text("Done")
                    })
            }
        }
        .sheet(isPresented: $isShowingInsights) {
            NavigationView {
                InsightsView(viewModel: viewModel.insightsViewModel)
                    .navigationBarItems(trailing: Button(action: { isShowingInsights = false }) {
                        Text("Done")
                    })
            }
        }
        .sheet(isPresented: $isShowingShareStore) {
            NavigationView {
                ShareStoreView(store: viewModel.store, isPresented: $isShowingShareStore)
            }.backport.presentationDetents([.medium])
           }
        .fullScreenCover(isPresented: $isDocumentBrowserPresented) {
            DocumentBrowser()
        }
    }

    private func buttonRemoveAllTapped() {
        viewModel.store.removeAll()

        runHapticFeedback(.success)
        ToastView {
            HStack {
                Image(systemName: "trash")
                Text("All messages removed")
            }
        }.show()
    }

    private func buttonSponsorTapped() {
        guard let url = URL(string: "https://github.com/sponsors/kean") else { return }
        UIApplication.shared.open(url)
    }

    private func buttonSendFeedbackTapped() {
        guard let url = URL(string: "https://github.com/kean/Pulse/issues") else { return }
        UIApplication.shared.open(url)
    }
}

private struct DocumentBrowser: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DocumentBrowserViewController {
        DocumentBrowserViewController(forOpeningContentTypes: [UTType(filenameExtension: "pulse")].compactMap { $0 })
    }

    func updateUIViewController(_ uiViewController: DocumentBrowserViewController, context: Context) {

    }
}
#endif
