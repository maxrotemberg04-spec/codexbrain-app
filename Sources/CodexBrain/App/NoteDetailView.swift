import SwiftUI
import WebKit
import AppKit

struct NoteDetailView: View {
    @EnvironmentObject var state: AppState
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        Group {
            if let note = state.selectedNote {
                VStack(spacing: 0) {
                    header(note)
                    Divider()
                    if editing {
                        TextEditor(text: $draft)
                            .font(.system(size: 13, design: .monospaced))
                            .lineSpacing(3)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(Theme.bg)
                    } else {
                        MarkdownWebView(html: MarkdownHTML.page(for: note)) { wikiName in
                            state.openWiki(wikiName)
                        }
                    }
                }
                .onChange(of: state.selectedNoteID) {
                    editing = false
                    draft = ""
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accent)
                    Text("Pick a note, or search")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg)
            }
        }
    }

    private func header(_ note: Note) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                state.showNoteList.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(state.showNoteList ? "Hide the note list (⌘\\)" : "Show the note list (⌘\\)")
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(note.rootName)/\(note.relativePath)")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if editing {
                Button("Save") { save(note) }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
            }
            Button(editing ? "Preview" : "Edit") {
                if editing {
                    editing = false
                } else {
                    draft = note.content
                    editing = true
                }
            }
            .controlSize(.small)
            Menu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([note.url])
                }
                Button("Open in Obsidian") {
                    let encoded = note.url.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                    if let url = URL(string: "obsidian://open?path=\(encoded)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(note.url.path, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Theme.bg)
    }

    private func save(_ note: Note) {
        state.save(note: note, content: draft)
        editing = false
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let onWiki: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onWiki: onWiki) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")  // no white flash in dark mode
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        let onWiki: (String) -> Void
        init(onWiki: @escaping (String) -> Void) { self.onWiki = onWiki }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
            if url.scheme == "codex" {
                let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .removingPercentEncoding ?? ""
                let resolved = name.isEmpty ? (url.host ?? "") : name
                DispatchQueue.main.async { self.onWiki(resolved) }
                return decisionHandler(.cancel)
            }
            if let scheme = url.scheme, ["http", "https", "mailto", "obsidian"].contains(scheme) {
                NSWorkspace.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
    }
}
