import Foundation

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
            return highResolutionURL(from: (match ?? results.first)?.artworkUrl100)
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
