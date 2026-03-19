import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

@MainActor
final class PosterImageLoader: ObservableObject {
    static let shared = PosterImageLoader()

    // Only the lightweight set of URLs is kept in memory; actual image data lives
    // in NSCache so the OS can evict it under memory pressure.
    @Published private(set) var loadedURLs: Set<URL> = []

    private let cache = NSCache<NSURL, PlatformImage>()

    func load(from url: URL?) async {
        guard let url else { return }
        guard cache.object(forKey: url as NSURL) == nil else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = PlatformImage(data: data) else { return }
            cache.setObject(image, forKey: url as NSURL)
            loadedURLs.insert(url)
        } catch {}
    }

    func image(for url: URL?) -> PlatformImage? {
        guard let url else { return nil }
        return cache.object(forKey: url as NSURL)
    }
}
