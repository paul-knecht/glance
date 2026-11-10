import Foundation

// The reasons a request to Claude can fail. The panel shows `message`.
enum ClaudeError: Error, Equatable {
    case noKey          // no API key has been set yet
    case offline        // no internet connection
    case unauthorized   // the API key was not accepted
    case noCredit       // the Anthropic account has no credit
    case busy           // rate limited or overloaded
    case refused        // the model declined to answer
    case failed         // anything else

    var message: String {
        switch self {
        case .noKey: return "Add an Anthropic API key to get answers: open the Glance app again and choose Set API key."
        case .offline: return "No internet connection."
        case .unauthorized: return "The API key was not accepted. Open the Glance app again and set it once more."
        case .noCredit: return "Your Anthropic account has no credit. Add credit in the Anthropic Console."
        case .busy: return "Claude is busy right now. Try again in a moment."
        case .refused: return "Claude declined to answer this."
        case .failed: return "Something went wrong. Try again."
        }
    }
}

// Sends one request to Claude and hands back the answer piece by piece.
enum ClaudeClient {

    // The Claude model to use. Change it here if you want a different one.
    static let model = "claude-haiku-5-5"

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // A session that keeps nothing: no cache and no cookies, neither on
    // disk nor in memory.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    // Builds the JSON we send to Claude.
    static func requestBody(system: String, user: String) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            // Send the answer in small pieces as it is written.
            "stream": true,
            "system": system,
            // These two make the first words arrive as quickly as possible:
            // no thinking phase before the answer, and low effort.
            "thinking": ["type": "disabled"],
            "output_config": ["effort": "low"],
            "messages": [
                ["role": "user", "content": user],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // Names the failure for a reply that was not a normal answer.
    static func error(statusCode: Int, body: Data) -> ClaudeError {
        let text = String(data: body, encoding: .utf8) ?? ""
        if statusCode == 401 { return .unauthorized }
        if statusCode == 402 || text.contains("credit balance") { return .noCredit }
        if statusCode == 429 || statusCode == 529 { return .busy }
        return .failed
    }

    // Starts the request. The returned stream yields the answer's text in
    // pieces and ends when the answer is complete; it throws a ClaudeError
    // if something goes wrong. Stopping to read the stream cancels the request.
    static func stream(system: String, user: String, apiKey: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let key = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { throw ClaudeError.noKey }

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 30
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
                    request.httpBody = try requestBody(system: system, user: user)

                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await session.bytes(for: request)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // The request never got an answer: no connection, or it took too long.
                        throw ClaudeError.offline
                    }

                    // Anything but 200 is an error report, not an answer. Read it and name it.
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if statusCode != 200 {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 10_000 { break }
                        }
                        throw ClaudeClient.error(statusCode: statusCode, body: body)
                    }

                    // Read the answer line by line and pass on the text.
                    var reducer = StreamReducer()
                    do {
                        for try await line in bytes.lines {
                            if let text = try reducer.handle(StreamParser.event(fromLine: line)) {
                                continuation.yield(text)
                            }
                        }
                    } catch let error as ClaudeError {
                        throw error
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // The connection broke in the middle of the answer.
                        throw ClaudeError.failed
                    }
                    try reducer.finish()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // If nobody is listening any more, stop the request.
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
