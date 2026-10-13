import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol HTTPPerforming: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTP: HTTPPerforming {
    var session: URLSession

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: ChatClientError.badPayload)
                }
            }
            task.resume()
        }
    }
}

/// Body for `POST /chat`. Matches `backend/chat_models.py`: `{ messages: [{ role, text, page?, photo? }] }`.
/// Conversation and message IDs stay on the domain model; the backend forbids extras.
/// A page is identity only. The server loads its text. Only the last item carries photo bytes.
/// `demo` is omitted on the normal path and whenever the newest user turn is about a page.
/// `garage` is omitted when there is nothing to send.
struct ChatHTTPBody: Encodable, Equatable {
    var messages: [Item]
    var demo: Demo?
    var garage: GarageChatContext?

    struct Item: Encodable, Equatable {
        var role: String
        var text: String
        var page: PageRef?
        var photo: Photo?

        enum CodingKeys: String, CodingKey {
            case role
            case text
            case page
            case photo
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(page, forKey: .page)
            try container.encodeIfPresent(photo, forKey: .photo)
        }
    }

    struct Photo: Encodable, Equatable {
        var mediaType = "image/jpeg"
        /// `JSONEncoder` writes `Data` as base64 by default.
        var data: Data

        enum CodingKeys: String, CodingKey {
            case mediaType = "media_type"
            case data
        }
    }

    struct Demo: Encodable, Equatable {
        var photoID: String

        enum CodingKeys: String, CodingKey {
            case photoID = "photo_id"
        }
    }

    init(
        _ conversation: Conversation,
        demoPhotoID: String? = nil,
        garage: GarageChatContext? = nil
    ) {
        let lastIndex = conversation.messages.indices.last
        messages = conversation.messages.enumerated().map { index, message in
            switch message {
            case let .user(user):
                let photo = index == lastIndex ? user.attachment?.plugPhoto : nil
                return Item(
                    role: "user",
                    text: user.text,
                    page: user.attachment?.page,
                    photo: photo.map { Photo(data: $0.jpegData) }
                )
            case let .assistant(assistant):
                return Item(role: "assistant", text: assistant.answer.text)
            }
        }
        let newestUser = messages.last(where: { $0.role == "user" })
        if let demoPhotoID, !demoPhotoID.isEmpty, newestUser?.page == nil {
            demo = Demo(photoID: demoPhotoID)
        } else {
            demo = nil
        }
        if let garage, !garage.isEmpty {
            self.garage = garage
        } else {
            self.garage = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case messages
        case demo
        case garage
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(demo, forKey: .demo)
        try container.encodeIfPresent(garage, forKey: .garage)
    }
}

/// Live `POST /chat` client. Base URL comes from `ChatClientConfiguration`.
public struct LiveChatClient: ChatClient, Sendable {
    private let configuration: ChatClientConfiguration
    private let http: any HTTPPerforming

    public init(configuration: ChatClientConfiguration, session: URLSession = .shared) {
        self.init(configuration: configuration, http: URLSessionHTTP(session: session))
    }

    init(configuration: ChatClientConfiguration, http: any HTTPPerforming) {
        self.configuration = configuration
        self.http = http
    }

    public func send(
        _ conversation: Conversation,
        demoPhotoID: String? = nil,
        garage: GarageChatContext? = nil
    ) async throws -> Answer {
        var urlRequest = URLRequest(url: configuration.chatURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = configuration.requestTimeout
        urlRequest.httpBody = try JSONEncoder().encode(
            ChatHTTPBody(conversation, demoPhotoID: demoPhotoID, garage: garage)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: urlRequest)
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatClientError.badPayload
        }
        guard httpResponse.statusCode == 200 else {
            throw ChatClientError.httpStatus(httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw ChatClientError.badPayload
        }
    }

    static func mapTransportError(_ error: Error) -> ChatClientError {
        if let clientError = error as? ChatClientError { return clientError }
        if let urlError = error as? URLError { return mapURLErrorCode(urlError.code.rawValue) }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return mapURLErrorCode(nsError.code) }
        return .offline
    }

    private static func mapURLErrorCode(_ code: Int) -> ChatClientError {
        switch code {
        case NSURLErrorTimedOut:
            .timeout
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff:
            .offline
        default:
            .offline
        }
    }
}
