import Foundation

// MARK: - Request / Response

struct MusicGenerateRequest: Codable {
    let lyrics: String?
    let prompt: String?
    let duration: Double
    let steps: Int
    let genre: String?
}

struct MusicGenerateResponse {
    let audioData: Data
    let generationTimeHeader: String?
    let totalTimeHeader: String?
    let durationHeader: String?
}

struct MusicHealthResponse: Codable {
    let status: String?
    let modelLoaded: Bool?
    let device: String?
    let gpuName: String?

    enum CodingKeys: String, CodingKey {
        case status
        case modelLoaded = "model_loaded"
        case device
        case gpuName = "gpu_name"
    }
}

enum MusicAPIError: LocalizedError {
    case invalidURL(String)
    case invalidHTTPResponse
    case httpStatus(Int, String)
    case invalidWAV
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid music API URL: \(s)"
        case .invalidHTTPResponse: return "Invalid HTTP response from music API"
        case .httpStatus(let code, let body): return "Music API HTTP \(code): \(body)"
        case .invalidWAV: return "Response is not valid WAV audio"
        case .cancelled: return "Music generation cancelled"
        }
    }
}

// MARK: - Client

/// Shared DiffRhythm music generation client used by Song Gen and Life Path.
actor MusicAPIClient {
    static let defaultBaseURL = "https://song.npro.ai"
    static let musicURLKey = "songGen.musicURL.v1"

    var baseURL: String
    var timeout: TimeInterval

    init(
        baseURL: String? = nil,
        timeout: TimeInterval = 120
    ) {
        if let baseURL, !baseURL.isEmpty {
            self.baseURL = baseURL
        } else {
            self.baseURL = UserDefaults.standard.string(forKey: Self.musicURLKey)
                ?? Self.defaultBaseURL
        }
        self.timeout = timeout
    }

    func setBaseURL(_ url: String) {
        baseURL = url
        UserDefaults.standard.set(url, forKey: Self.musicURLKey)
    }

    func health() async throws -> MusicHealthResponse {
        let url = try makeURL(path: "/health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = min(timeout, 30)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        return try JSONDecoder().decode(MusicHealthResponse.self, from: data)
    }

    func generate(_ requestBody: MusicGenerateRequest) async throws -> MusicGenerateResponse {
        let url = try makeURL(path: "/music/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        guard data.count > 44, Self.isWAVData(data) else {
            throw MusicAPIError.invalidWAV
        }

        let http = response as? HTTPURLResponse
        return MusicGenerateResponse(
            audioData: data,
            generationTimeHeader: http?.value(forHTTPHeaderField: "X-Generation-Time"),
            totalTimeHeader: http?.value(forHTTPHeaderField: "X-Total-Time"),
            durationHeader: http?.value(forHTTPHeaderField: "X-Duration-Seconds")
        )
    }

    /// RIFF WAV header check (shared by Song Gen and Life Path).
    static func isWAVData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]) // "RIFF"
    }

    // MARK: - Private

    private func makeURL(path: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + path) else {
            throw MusicAPIError.invalidURL(baseURL)
        }
        return url
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MusicAPIError.invalidHTTPResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MusicAPIError.httpStatus(http.statusCode, body)
        }
    }
}
