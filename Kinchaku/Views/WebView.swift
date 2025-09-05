//
//  WebView.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
  let fileURL: URL
  let allowDir: URL
  func makeUIView(context: Context) -> WKWebView {
    let cfg = WKWebViewConfiguration()
    cfg.allowsInlineMediaPlayback = true
    let wv = WKWebView(frame: .zero, configuration: cfg)
    wv.loadFileURL(fileURL, allowingReadAccessTo: allowDir)
    return wv
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// Minimal preview that renders a tiny HTML string into a temp file
#Preview {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewWebView", isDirectory: true)
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let file = dir.appendingPathComponent("index.html")
  try? "<html><body><h1>Preview</h1><p>Hello!</p></body></html>".data(using: .utf8)?.write(to: file)
  return WebView(fileURL: file, allowDir: dir)
    .frame(height: 240)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding()
}
