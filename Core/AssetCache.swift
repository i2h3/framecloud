// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation
import os

/// `AssetCache` downloads remote assets into the shared App Group container's caches directory and avoids redundant downloads by revalidating cached copies with the server using their HTTP `ETag`.
///
/// `AccountStore.persist(theming:)` uses the `shared` instance to keep local copies of the Nextcloud server's branding assets up to date so they can be displayed without re-fetching them every launch.
/// Cached files are addressed by the SHA-256 digest of their absolute URL so that distinct remote URLs map to distinct local files.
final class AssetCache: Sendable {
    /// `shared` is the process-wide cache instance.
    ///
    /// `AccountStore.persist(theming:)` uses it to cache the server's branding assets, and other parts of the app read those cached files back via `localURL(for:)`.
    static let shared = AssetCache()

    /// `logger` records asset caching activity under the `AssetCache` category.
    private let logger = Logger(for: AssetCache.self)

    /// `directory` is the on-disk location, rooted in the shared App Group container's caches directory, in which cached asset payloads and their `ETag` sidecars are stored.
    private let directory: URL

    /// `session` is the `URLSession` used to download assets.
    private let session: URLSession

    /// `init()` creates the cache over the directory `assetsDirectory()` resolved.
    init() {
        directory = Self.assetsDirectory()
        session = .shared
    }

    /// `assetsDirectory()` is the directory cached payloads and their `ETag` sidecars live in, created if it does not exist yet.
    ///
    /// It is the `Assets` subdirectory of the shared App Group container's `Library/Caches`, so a future app extension sharing the same App Group reaches the same cached assets. A build that cannot reach that container — an ad-hoc one, which carries no App Group entitlement and is what a fresh clone, a fork, and CI produce — falls back to the app's own caches directory instead, so branding assets still cache for it rather than the whole feature failing. The fallback is chosen by *attempting* the shared location rather than by inspecting `AppGroup.containerURL`, because the container path can resolve while the sandbox still refuses to create anything under it, and only the attempt tells those two apart.
    private static func assetsDirectory() -> URL {
        let logger = Logger(for: AssetCache.self)
        let sharedDirectory = AppGroup.containerURL?
            .appending(path: "Library/Caches", directoryHint: .isDirectory)
            .appending(component: "Assets", directoryHint: .isDirectory)

        if let sharedDirectory {
            do {
                try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
                logger.debug("Cache directory ready in the App Group container")
                return sharedDirectory
            } catch {
                logger.error("Could not create the cache directory in the App Group container; falling back to this build's own: \(error.localizedDescription)")
            }
        } else {
            logger.notice("No App Group container resolved; caching assets in this build's own container")
        }

        let ownDirectory = URL.cachesDirectory.appending(component: "Assets", directoryHint: .isDirectory)

        do {
            try FileManager.default.createDirectory(at: ownDirectory, withIntermediateDirectories: true)
            logger.debug("Cache directory ready in this build's own container")
        } catch {
            logger.error("Could not create the cache directory: \(error.localizedDescription)")
        }

        return ownDirectory
    }

    /// `clear()` removes every cached payload and `ETag` sidecar stored by this cache.
    ///
    /// `AccountStore.disconnect()` invokes this when the user disconnects from the server, so that nothing describing a server the app no longer talks to is left on disk — the branding it was themed with, and the icons of the apps it offered.
    /// It removes the files it owns rather than the directory holding them. `directory` is inside the shared App Group container by design, so that an app extension reaches the same copies, and removing the directory itself would take a subdirectory another writer had made with it. Everything loose in `Assets/` belongs to whichever account is connected and goes when that account goes; anything that ever needs to outlive one belongs in a subdirectory, which this now leaves standing.
    func clear() {
        let contents: [URL]

        do {
            contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsSubdirectoryDescendants)
        } catch {
            logger.debug("Could not list the cache directory (it may not exist yet): \(error.localizedDescription)")
            return
        }

        var removed = 0

        for file in contents {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }

            do {
                try FileManager.default.removeItem(at: file)
                removed += 1
            } catch {
                logger.error("Could not remove a cached asset: \(error.localizedDescription)")
            }
        }

        logger.debug("Cleared \(removed) cached asset(s)")
    }

    /// `localURL(for:)` returns the file system URL of the cached copy of `remoteURL`, or `nil` if no copy has been downloaded yet.
    ///
    /// Call this from UI code that wants to display a cached asset; if it returns `nil`, the asset has not been downloaded yet and a placeholder should be shown instead.
    func localURL(for remoteURL: URL) -> URL? {
        localURL(forKey: remoteURL.absoluteString)
    }

    /// `localURL(forKey:)` returns the file system URL of the copy cached under `key`, or `nil` if none has been downloaded yet.
    ///
    /// A caller that knows what it is looking for before it knows where that came from uses this. Server app icons are the case in point: the menus have an app's identifier at launch but not the path the server will next say its icon lives at, so they are cached under a key built from the two things a menu does hold, and found again without the network having been reached.
    func localURL(forKey key: String) -> URL? {
        let fileURL = fileURL(forKey: key)

        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            logger.debug("Cache miss for \(key, privacy: .public)")
            return nil
        }

        logger.debug("Cache hit for \(key, privacy: .public)")
        return fileURL
    }

    /// `data(forKey:)` is the bytes cached under `key`, or `nil` if nothing is cached or they cannot be read.
    func data(forKey key: String) -> Data? {
        guard let fileURL = localURL(forKey: key) else {
            return nil
        }

        return try? Data(contentsOf: fileURL)
    }

    /// `cache(remote:)` downloads the asset at `remoteURL` into the cache directory, unless the server confirms via the `ETag` sent in `If-None-Match` that the cached copy is still up to date.
    ///
    /// Returns the file system URL of the cached copy.
    /// Throws `CirruscopeError.invalidResponse` if the server response is not HTTP, `CirruscopeError.unexpectedStatus` for HTTP status codes outside 2xx and 304, and any error thrown by `URLSession` while transporting the request.
    @discardableResult
    func cache(remote remoteURL: URL) async throws -> URL {
        try await cache(remote: remoteURL, key: nil, authenticatedAs: nil)
    }

    /// `cache(remote:key:authenticatedAs:)` downloads the asset at `remoteURL`, storing it under `key` and identifying the user with `credentials`.
    ///
    /// `key` defaults to the URL itself, which is what a caller that will look the asset up by the same URL wants. Passing one instead stores the asset where a caller can find it knowing something more durable than the path — an app's identifier rather than the icon path the server currently gives it.
    /// `credentials` are attached as HTTP Basic authentication, and only ever for a `SameOriginURL`, which is what proves the request is going to the server that named it rather than somewhere that server was persuaded to point at. They matter more than they look: an instance that requires authentication for its assets does not answer with a `401` but with its sign-in page under a `200`, so an unauthenticated request quietly caches an HTML document where an image should be.
    @discardableResult
    func cache(remote asset: SameOriginURL, key: String? = nil, authenticatedAs credentials: Credentials? = nil) async throws -> URL {
        try await cache(remote: asset.url, key: key, authenticatedAs: credentials)
    }

    /// `cache(remote:key:authenticatedAs:)` is the transfer itself, shared by the two entry points above.
    @discardableResult
    private func cache(remote remoteURL: URL, key: String?, authenticatedAs credentials: Credentials?) async throws -> URL {
        let fileURL = fileURL(forKey: key ?? remoteURL.absoluteString)
        let localETag = etag(for: fileURL)

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let credentials {
            request.setValue(credentials.basicAuthorizationValue, forHTTPHeaderField: "Authorization")
        }

        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)), let localETag {
            request.setValue(localETag, forHTTPHeaderField: "If-None-Match")
            logger.debug("Revalidating \(remoteURL, privacy: .public) with locally cached ETag \(localETag, privacy: .public)")
        } else {
            logger.debug("Requesting \(remoteURL, privacy: .public) unconditionally; no locally cached ETag")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Non-HTTP response caching \(remoteURL, privacy: .public)")
            throw CirruscopeError.invalidResponse
        }

        let serverETag = httpResponse.value(forHTTPHeaderField: "ETag") ?? "none"

        switch httpResponse.statusCode {
            case 304:
                logger.debug("Asset not modified (HTTP 304) for \(remoteURL, privacy: .public); server ETag \(serverETag, privacy: .public)")
                return fileURL
            case 200 ..< 300:
                try data.write(to: fileURL, options: .atomic)
                if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
                    setETag(newETag, for: fileURL)
                } else {
                    removeETag(for: fileURL)
                }
                logger.info("Cached asset (HTTP \(httpResponse.statusCode)) for \(remoteURL, privacy: .public); server ETag \(serverETag, privacy: .public)")
                return fileURL
            default:
                logger.error("Unexpected status \(httpResponse.statusCode) caching \(remoteURL, privacy: .public)")
                throw CirruscopeError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    /// `fileURL(forKey:)` returns the file system URL at which the copy cached under `key` is stored.
    ///
    /// The file name is the lowercase hex-encoded SHA-256 digest of `key`, so that the mapping is deterministic and collision resistant whatever the key is spelled like — a URL, or an identifier a caller composed.
    /// It carries no file extension, and deliberately so: nothing reads these back by type. The only reader that ever sniffed one was `NSImage(contentsOf:)`, which sniffs content rather than names, and adding an extension now would change every existing file name and orphan every copy already cached.
    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(component: name)
    }

    /// `etagURL(for:)` returns the file system URL of the `ETag` sidecar file that accompanies the cached payload at `fileURL`.
    private func etagURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("etag")
    }

    /// `etag(for:)` reads the `ETag` previously persisted alongside the cached payload at `fileURL`, or returns `nil` if none has been recorded.
    private func etag(for fileURL: URL) -> String? {
        try? String(contentsOf: etagURL(for: fileURL), encoding: .utf8)
    }

    /// `setETag(_:for:)` persists `etag` alongside the cached payload at `fileURL` so subsequent downloads can revalidate the cached copy.
    private func setETag(_ etag: String, for fileURL: URL) {
        try? etag.write(to: etagURL(for: fileURL), atomically: true, encoding: .utf8)
    }

    /// `removeETag(for:)` deletes the `ETag` sidecar for `fileURL`, if one exists, so that the next download is unconditional.
    private func removeETag(for fileURL: URL) {
        try? FileManager.default.removeItem(at: etagURL(for: fileURL))
    }
}
