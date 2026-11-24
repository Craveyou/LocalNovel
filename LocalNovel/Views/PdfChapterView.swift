import SwiftUI
import UIKit
import PDFKit

// MARK: - 漫画 pdf 单话：按页纵向渲染
//
// 漫画体积大，不能一次性把所有页转成图：每页在可见时才异步渲染，
// 离屏即由 SwiftUI 释放；PDFDocument 按路径缓存，避免反复解析同一个文件。
// 全程本地、无联网。

final class PdfPageRenderer: @unchecked Sendable {
    static let shared = PdfPageRenderer()

    private let queue = DispatchQueue(label: "localnovel.pdf.render", qos: .userInitiated)
    private let lock = NSLock()
    private var documents: [String: PDFDocument] = [:]

    func pageCount(_ url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return documentLocked(url)?.pageCount ?? 0
    }

    func image(url: URL, page: Int, maxPixel: CGFloat) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            queue.async {
                self.lock.lock()
                let doc = self.documentLocked(url)
                self.lock.unlock()
                guard let doc, let pageRef = doc.page(at: page) else {
                    continuation.resume(returning: nil)
                    return
                }
                let box = pageRef.bounds(for: .mediaBox)
                guard box.width > 1, box.height > 1 else {
                    continuation.resume(returning: nil)
                    return
                }
                let width = max(600, maxPixel)
                let height = width * box.height / box.width
                let image = pageRef.thumbnail(of: CGSize(width: width, height: height), for: .mediaBox)
                continuation.resume(returning: image)
            }
        }
    }

    /// 调用方需持有 lock
    private func documentLocked(_ url: URL) -> PDFDocument? {
        if let cached = documents[url.path] { return cached }
        guard let doc = PDFDocument(url: url) else { return nil }
        if documents.count > 3 { documents.removeAll() }
        documents[url.path] = doc
        return doc
    }
}

struct PdfChapterView: View {
    let url: URL

    @State private var pageCount = 0
    @State private var didFail = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if didFail {
                    ContentUnavailableView("无法打开这个 PDF",
                                           systemImage: "doc.questionmark",
                                           description: Text(url.lastPathComponent))
                        .padding(.top, 40)
                } else if pageCount == 0 {
                    ProgressView("正在读取 \(url.lastPathComponent)…")
                        .padding(.top, 60)
                } else {
                    ForEach(0..<pageCount, id: \.self) { index in
                        PdfPageView(url: url, index: index)
                    }
                    Text("\(pageCount) 页 · 完")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
        }
        .task {
            let count = await Task.detached(priority: .userInitiated) {
                PdfPageRenderer.shared.pageCount(url)
            }.value
            pageCount = count
            didFail = count == 0
        }
    }
}

private struct PdfPageView: View {
    let url: URL
    let index: Int

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 320)
                    .overlay(ProgressView())
            }
        }
        .task {
            guard image == nil else { return }
            image = await PdfPageRenderer.shared.image(url: url, page: index, maxPixel: 1200)
        }
    }
}
