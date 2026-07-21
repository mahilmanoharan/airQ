import Foundation

public enum ErrorType: LocalizedError {
    case networkError
    case codingError
    case invalidURL
    case unknown

    public var errorDescription: String? {
        switch self {
        case .networkError:
            return "A network error occurred. Please check your connection."
        case .codingError:
            return "Failed to encode/decode data."
        case .invalidURL:
            return "The URL provided is invalid."
        case .unknown:
            return "An unknown error occurred."
        }
    }
}
