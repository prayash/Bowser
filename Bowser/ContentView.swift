//
//  ContentView.swift
//  Bowser
//
//  Created by Prayash Thapa on 3/9/25.
//  Copyright © 2025 prayash.io. All rights reserved.
//

import Observation
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
    
    func takeSnapshot() async throws -> NSImage {
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
    var snapshot: (_ takeSnapshot: @escaping () async -> NSImage) -> Void
    
    class Coordinator: NSObject, WKNavigationDelegate {
        
    }
    
    func makeCoordinator() -> Coordinator {
        .init()
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let result = WKWebView()
        result.navigationDelegate = context.coordinator
        return result
    }
    
    func updateNSView(_ webView: NSViewType, context: Context) {
        assert(Thread.isMainThread)
        
        context.environment.webViewBox?.value = webView
        snapshot({
            assert(Thread.isMainThread)
            return try! await webView.takeSnapshot(configuration: nil)
//            await withCheckedContinuation { continuation in
//                webView.takeSnapshot(with: nil) { image, error in
//                    continuation.resume(returning: image!)
//                }
//            }
        })
        
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

extension NSImage: @unchecked Sendable {}

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
                    WebView(url: page.url, snapshot: { takeSnapshot in
                        self.takeSnapshot = takeSnapshot
                    })
                    .toolbar {
                        Button("Snapshot Alt") {
                            Task {
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
            ToolbarItem {
                Button("Take Snapshot") {
                    Task {
                        image = await takeSnapshot?()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
