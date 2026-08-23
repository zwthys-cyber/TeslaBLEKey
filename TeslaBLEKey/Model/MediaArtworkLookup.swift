import Foundation
import NeteaseCloudMusicAPI

enum MediaArtworkLookup {
    private struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    private struct SearchResult: Decodable {
        let trackName: String?
        let artistName: String?
        let artworkUrl100: URL?
    }

    static func artworkURL(title: String, artist: String?) async -> URL? {
        if let result = await neteaseArtworkURL(title: title, artist: artist) {
            return result
        }
        return await appleArtworkURL(title: title, artist: artist)
    }

    private static func neteaseArtworkURL(title: String, artist: String?) async -> URL? {
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
            guard let rawURL = album?["picUrl"] as? String,
                  var components = URLComponents(string: rawURL) else { return nil }
            // NetEase search responses may still use an http artwork URL.
            // iOS ATS blocks it inside AsyncImage, while the same CDN supports
            // TLS, so always upgrade the image request to HTTPS.
            components.scheme = "https"
            components.queryItems = [URLQueryItem(name: "param", value: "300y300")]
            return components.url
        } catch {
            return nil
        }
    }

    private static func appleArtworkURL(title: String, artist: String?) async -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: [title, artist].compactMap { $0 }.joined(separator: " ")),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
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
            return highResolutionURL(from: match?.artworkUrl100)
        } catch {
            return nil
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
