import Foundation

/// Thin async client over the MOEX ISS HTTP API (`iss.moex.com/iss/`).
/// An actor so a single instance can be shared across the app safely.
public actor ISSClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://iss.moex.com/iss/")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches and decodes an ISS document for `path` (relative to the ISS base).
    func fetchDocument(path: String, query: [URLQueryItem]) async throws -> ISSDocument {
        let full = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: full, resolvingAgainstBaseURL: false) else {
            throw ExchangeError.network("Invalid URL for \(path)")
        }
        components.queryItems = query
        guard let url = components.url else {
            throw ExchangeError.network("Invalid query for \(path)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw ExchangeError.network(String(describing: error))
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ExchangeError.network("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(ISSDocument.self, from: data)
        } catch {
            throw ExchangeError.decoding(String(describing: error))
        }
    }
}
