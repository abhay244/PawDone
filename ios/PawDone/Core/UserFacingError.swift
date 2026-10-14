import Foundation
import os
import Supabase

enum UserFacingError {
    private static let logger = Logger(subsystem: "com.abhaysingh.pawdone", category: "errors")

    /// The database's own wording for rule violations (raised with P0001/P0002 in the
    /// migrations), and a generic message for anything technical. The full error is
    /// logged so it shows in Xcode's console.
    static func message(for error: any Error) -> String {
        logger.error("\(String(describing: error), privacy: .public)")

        if let error = error as? PostgrestError, let code = error.code, ["P0001", "P0002"].contains(code) {
            return error.message
        }
        if let error = error as? NotSignedIn, let description = error.errorDescription {
            return description
        }
        return "Something went wrong. Check your connection and try again."
    }
}
