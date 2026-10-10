import Foundation
struct BackendFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
