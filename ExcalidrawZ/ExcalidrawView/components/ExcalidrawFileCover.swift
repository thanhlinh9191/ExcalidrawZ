//
//  ExcalidrawFileCover.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/1/26.
//

import SwiftUI
import ChocofordUI

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

class FileItemPreviewCache: NSCache<NSString, PlatformImage> {
    static let shared = FileItemPreviewCache()
    
    static func cacheKey(forID id: String, colorScheme: ColorScheme) -> NSString {
        (id + (colorScheme == .light ? "_light" : "_dark")) as NSString
    }
    
    func getPreviewCache(forID id: String, colorScheme: ColorScheme) -> PlatformImage? {
        self.object(forKey: Self.cacheKey(forID: id, colorScheme: colorScheme))
    }
    
    func removePreviewCache(forID id: String, colorScheme: ColorScheme) {
        self.removeObject(forKey: Self.cacheKey(forID: id, colorScheme: colorScheme))
    }

    func removePreviewCache(forID id: String) {
        self.removePreviewCache(forID: id, colorScheme: .light)
        self.removePreviewCache(forID: id, colorScheme: .dark)
    }
}



struct ExcalidrawFileCover: View {
    @Environment(\.colorScheme) var colorScheme
    
    // Support two initialization modes
    private enum Source {
        case activeFile(FileState.ActiveFile)
        case excalidrawFile(ExcalidrawFile)
    }
    
    private let source: Source
    private let refreshToken: String?
    private let allowsGeneration: Bool
    
    init(
        file: FileState.ActiveFile,
        refreshToken: String? = nil,
        allowsGeneration: Bool = true
    ) {
        self.source = .activeFile(file)
        self.refreshToken = refreshToken
        self.allowsGeneration = allowsGeneration
    }
    
    init(
        excalidrawFile: ExcalidrawFile,
        refreshToken: String? = nil,
        allowsGeneration: Bool = true
    ) {
        self.source = .excalidrawFile(excalidrawFile)
        self.refreshToken = refreshToken
        self.allowsGeneration = allowsGeneration
    }
    
    var fileID: String {
        switch source {
            case .activeFile(let file):
                return file.id
            case .excalidrawFile(let file):
                return file.id
        }
    }
    
    let cache = FileItemPreviewCache.shared
    
    @State private var coverImage: Image? = nil
    
    var body: some View {
        previewContent
            .apply { view in
                applyListeners(to: view)
            }
            .onAppear {
                updateCoverFromCache()
            }
            .watch(value: colorScheme) { _ in
                updateCoverFromCache()
            }
            .watch(value: refreshToken ?? "default") { _ in
                updateCoverFromCache()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .filePreviewShouldRefresh)
            ) { notification in
                guard let fileID = notification.object as? String,
                      self.fileID == fileID else { return }

                requestCoverRefresh(forceRefresh: true)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .filePreviewDidUpdate)
            ) { notification in
                guard let fileID = notification.object as? String,
                      self.fileID == fileID else { return }

                updateCoverFromCache()
            }
    }
    
    @ViewBuilder
    private var previewContent: some View {
        ZStack {
            if let coverImage {
                coverImage
                    .resizable()
            } else if let cachedImage {
                cachedImage
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.08 : 0.06))
            }
        }
    }

    private var cachedImage: Image? {
        guard let image = cache.getPreviewCache(forID: fileID, colorScheme: colorScheme) else {
            return nil
        }
        return Image(platformImage: image)
    }
    
    @ViewBuilder
    private func applyListeners<V: View>(to view: V) -> some View {
        switch source {
            case .activeFile(let file):
                // Apply all listeners for ActiveFile
                view
                    .observeFileStatus(for: file) { status in
#if os(macOS)
                        if status.iCloudStatus == .outdated {
                            self.requestCoverRefresh(forceRefresh: true)
                        }
#endif
                    }
            case .excalidrawFile:
                view
        }
    }

    @discardableResult
    private func showCachedCoverIfAvailable() -> Bool {
        guard let image = cache.getPreviewCache(forID: fileID, colorScheme: colorScheme) else {
            return false
        }

        coverImage = Image(platformImage: image)
        return true
    }

    private func updateCoverFromCache() {
        if !showCachedCoverIfAvailable() {
            coverImage = nil
        }
    }

    private func requestCoverRefresh(forceRefresh: Bool) {
        guard allowsGeneration else { return }

        let coordinatorSource: FileCoverCacheCoordinator.Source = {
            switch source {
                case .activeFile(let file):
                    return .activeFile(file)
                case .excalidrawFile(let file):
                    return .excalidrawFile(file)
            }
        }()

        FileCoverCacheCoordinator.shared.request(
            source: coordinatorSource,
            colorScheme: colorScheme,
            priority: .userInitiated,
            forceRefresh: forceRefresh
        )
    }
}

#if canImport(AppKit)
extension NSImage {
    func downsampledCGImage(maxPixelSize: CGFloat) -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        guard let cgImage = self.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = maxPixelSize / max(width, height)
        let targetSize = CGSize(width: max(1, width * scale), height: max(1, height * scale))

        guard let ctx = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        return ctx.makeImage()
    }
}
#endif

#if canImport(UIKit)
extension UIImage {
    func downsampledCGImage(maxPixelSize: CGFloat) -> CGImage? {
        let cgImage: CGImage
        if let image = self.cgImage {
            cgImage = image
        } else if let ciImage = self.ciImage {
            let context = CIContext(options: nil)
            guard let image = context.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            cgImage = image
        } else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = maxPixelSize / max(width, height)
        let targetSize = CGSize(width: max(1, width * scale), height: max(1, height * scale))

        guard let ctx = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        return ctx.makeImage()
    }
}
#endif
