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

    @Published private(set) var images: [URL: PlatformImage] = [:]

    private let cache = NSCache<NSURL, PlatformImage>()

    func load(from url: URL?) async {
        guard let url else {
            return
        }

        if let cached = cache.object(forKey: url as NSURL) {
            images[url] = cached
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = PlatformImage(data: data) else {
                return
            }

            cache.setObject(image, forKey: url as NSURL)
            images[url] = image
        } catch {
        }
    }

    func image(for url: URL?) -> PlatformImage? {
        guard let url else {
            return nil
        }

        if let image = images[url] {
            return image
        }

        return cache.object(forKey: url as NSURL)
    }
}
