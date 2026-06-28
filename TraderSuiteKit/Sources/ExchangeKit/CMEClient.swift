import Foundation

/// Thin async HTTP client over the CME Group public data API.
/// Base URL: https://www.cmegroup.com/CmeWS/mvc/
///
/// CME does not require authentication for these settlement and margin endpoints.
/// Headers mimic a browser request to avoid being rejected.
public actor CMEClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://www.cmegroup.com/CmeWS/mvc/")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Initial-margin schedule for `productCode`.
    func fetchMargins(productCode: String) async throws -> CMEMarginsDocument {
        try await fetch(
            path: "Margins/initialMargins.json",
            query: [URLQueryItem(name: "productCode", value: productCode)]
        )
    }

    // MARK: Private

    private func fetch<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> T {
        let full = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: full, resolvingAgainstBaseURL: false) else {
            throw ExchangeError.network("Invalid URL for \(path)")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw ExchangeError.network("Invalid query for \(path)")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.cmegroup.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ExchangeError.network(String(describing: error))
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ExchangeError.network("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ExchangeError.decoding(String(describing: error))
        }
    }
}
