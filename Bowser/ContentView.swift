//
//  ContentView.swift
//  Bowser
//
//  Created by Prayash Thapa on 3/9/25.
//  Copyright © 2025 prayash.io. All rights reserved.
//

import Observation
import SQLite3
import SwiftUI
import WebKit

class Box<A> {
    var value: A
    init(_ value: A) {
        self.value = value
    }
}

struct NoWebViewError: Error {}

struct WebViewProxy {
    var box: Box<WKWebView?> = Box(nil)
    
    @MainActor func takeSnapshot() async throws -> NSImage {
        guard let w = box.value else { throw NoWebViewError() }
        return try await w.takeSnapshot(configuration: nil)
    }
}

extension EnvironmentValues {
    @Entry var webViewBox: Box<WKWebView?>?
}

struct WebViewReader<Content: View>: View {
    @State private var proxy = WebViewProxy()
    @ViewBuilder var content: (WebViewProxy) -> Content
    
    var body: some View {
        content(proxy)
            .environment(\.webViewBox, proxy.box)
    }
}

struct WebView: NSViewRepresentable {
    var url: URL

    class Coordinator: NSObject, WKNavigationDelegate {}
    
    func makeCoordinator() -> Coordinator { .init() }
    
    func makeNSView(context: Context) -> WKWebView {
        let result = WKWebView()
        result.navigationDelegate = context.coordinator
        return result
    }
    
    func updateNSView(_ webView: NSViewType, context: Context) {
        assert(Thread.isMainThread)
        context.environment.webViewBox?.value = webView
        
        if webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
}

struct Page: Identifiable, Hashable {
    var id = UUID()
    var url: URL
}

@Observable class Store {
    var pages: [Page] = [
        .init(url: URL(string: "https://prayash.io")!),
        .init(url: URL(string: "https://apple.com")!)
    ]
    
    func submit(url: URL) {
        pages.append(Page(url: url))
    }
}

struct ContentView: View {
    
    @State var store = Store()
    @State var currentURLString: String = "https://prayash.io"
    @State var selectedPage: Page.ID?
    @State var image: NSImage?
    @State var takeSnapshot: (() async -> NSImage)?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                ForEach(store.pages) { page in
                    Text(page.url.absoluteString)
                }
            }
        } detail: {
            if let selectedPage, let page = store.pages.first(where: { $0.id == selectedPage }) {
                WebViewReader { proxy in
                    WebView(url: page.url)
                        .toolbar {
                            Button("Snapshot") {
                                Task {
                                    // Task inherits MainActor-context here.
                                    // But the next `await` call doesn't – it 'hops'
                                    // to another execution context which we don't control.
                                    // So we can mark the proxy method as MainActor to ensure
                                    // the WKWebView's snapshot is captured properly.
                                    image = try await proxy.takeSnapshot()
                                }
                            }
                        }
                }
                .overlay {
                    if let i = image {
                        Image(nsImage: i)
                            .scaleEffect(0.5)
                            .border(Color.red)
                    }
                }
            } else {
                ContentUnavailableView("No page selected", systemImage: "globe")
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("URL", text: $currentURLString)
                    .onSubmit {
                        if let url = URL(string: currentURLString) {
                            currentURLString = ""
                            store.submit(url: url)
                        }
                    }
            }
        }
    }
}

#Preview {
    ContentView()
}
