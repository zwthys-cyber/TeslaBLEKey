import Foundation
import NeteaseCloudMusicAPI

enum MediaArtworkLookup {
    struct Metadata: Sendable {
        let artworkURL: URL?
        let durationSeconds: Int?
    }
    private struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    private struct SearchResult: Decodable {
        let trackName: String?
        let artistName: String?
        let artworkUrl100: URL?
        let trackTimeMillis: Int?
    }

    static func metadata(title: String, artist: String?) async -> Metadata {
        if let result = await neteaseMetadata(title: title, artist: artist) {
            return result
        }
        return await appleMetadata(title: title, artist: artist)
    }

    private static func neteaseMetadata(title: String, artist: String?) async -> Metadata? {
        do {
            let keywords = [title, artist].compactMap { $0 }.joined(separator: " ")
            let response = try await NCMClient().cloudsearch(keywords: keywords, type: .single, limit: 5)
            guard let result = response.body["result"] as? [String: Any],
                  let songs = result["songs"] as? [[String: Any]] else { return nil }
            let normalizedTitle = normalize(title)
            let normalizedArtist = artist.map(normalize)
            let match = songs.first { song in
                guard let name = song["name"] as? String, normalize(name) == normalizedTitle else { return false }
                guard let normalizedArtist else { return true }
                let artists = (song["ar"] as? [[String: Any]] ?? song["artists"] as? [[String: Any]]) ?? []
                return artists.compactMap { $0["name"] as? String }
                    .map(normalize)
                    .contains { $0.contains(normalizedArtist) || normalizedArtist.contains($0) }
            }
            guard let match else { return nil }
            let album = match["al"] as? [String: Any] ?? match["album"] as? [String: Any]
            let duration = (match["dt"] as? Int ?? match["duration"] as? Int).map { $0 / 1000 }
            guard let rawURL = album?["picUrl"] as? String, var components = URLComponents(string: rawURL) else {
                return Metadata(artworkURL: nil, durationSeconds: duration)
            }
            // NetEase search responses may still use an http artwork URL.
            // iOS ATS blocks it inside AsyncImage, while the same CDN supports
            // TLS, so always upgrade the image request to HTTPS.
            components.scheme = "https"
            components.queryItems = [URLQueryItem(name: "param", value: "300y300")]
            return Metadata(artworkURL: components.url, durationSeconds: duration)
        } catch {
            return nil
        }
    }

    private static func appleMetadata(title: String, artist: String?) async -> Metadata {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: [title, artist].compactMap { $0 }.joined(separator: " ")),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url else { return Metadata(artworkURL: nil, durationSeconds: nil) }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return Metadata(artworkURL: nil, durationSeconds: nil)
            }
            let results = try JSONDecoder().decode(SearchResponse.self, from: data).results
            let normalizedTitle = normalize(title)
            let normalizedArtist = artist.map(normalize)
            let match = results.first { result in
                guard let resultTitle = result.trackName, normalize(resultTitle) == normalizedTitle else { return false }
                guard let normalizedArtist else { return true }
                return result.artistName.map(normalize)?.contains(normalizedArtist) == true
            }
            // A wrong cover is worse than the neutral fallback. Only accept an
            // exact normalized title and artist match across music services.
            return Metadata(artworkURL: highResolutionURL(from: match?.artworkUrl100),
                            durationSeconds: match?.trackTimeMillis.map { $0 / 1000 })
        } catch {
            return Metadata(artworkURL: nil, durationSeconds: nil)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }

    private static func highResolutionURL(from url: URL?) -> URL? {
        guard let url else { return nil }
        return URL(string: url.absoluteString.replacingOccurrences(of: "100x100bb", with: "300x300bb"))
    }
}
