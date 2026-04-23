import Foundation

#if canImport(UIKit)
import UIKit
#endif

final class AttributionNetwork {
    struct ResponseEnvelope<Response: Decodable> {
        let body: Response
        let rawPayload: [String: Any]?
    }

    enum NetworkError: Error {
        case invalidURL
        case invalidResponse
        case requestFailed(Int)
    }

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    static let requestTimeout: TimeInterval = 15

    func post<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        config: AttributionConfig,
        completion: @escaping (Result<ResponseEnvelope<Response>, Error>) -> Void
    ) {
        guard let url = URL(string: normalizedURL(path: path, baseURL: config.baseURL)) else {
            completion(.failure(NetworkError.invalidURL))
            return
        }

        var request = URLRequest(url: url, timeoutInterval: AttributionNetwork.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let data, let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NetworkError.invalidResponse))
                return
            }

            guard 200 ..< 300 ~= httpResponse.statusCode else {
                completion(.failure(NetworkError.requestFailed(httpResponse.statusCode)))
                return
            }

            do {
                let decoded = try decoder.decode(Response.self, from: data)
                let rawPayload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                completion(.success(ResponseEnvelope(body: decoded, rawPayload: rawPayload)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func idfv() -> String? {
        #if canImport(UIKit)
        UIDevice.current.identifierForVendor?.uuidString
        #else
        nil
        #endif
    }

    func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
    }

    func systemVersion() -> String {
        #if canImport(UIKit)
        UIDevice.current.systemVersion
        #else
        ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    func userAgent(appId: String) -> String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? appId
        return [
            bundleIdentifier,
            "/",
            appVersion(),
            " (iOS ",
            systemVersion(),
            "; ",
            deviceModel(),
            ")"
        ].joined()
    }

    private func normalizedURL(path: String, baseURL: String) -> String {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return trimmedBase + normalizedPath
    }
}
