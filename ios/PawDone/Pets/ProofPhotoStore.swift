import UIKit

/// Keeps photo proof on this phone, one JPEG per occurrence.
///
/// Free plan photos never leave the phone. They live in Application Support, which is
/// included in iPhone and iCloud backups.
struct ProofPhotoStore {
    var directory = URL.applicationSupportDirectory.appending(path: "ProofPhotos", directoryHint: .isDirectory)

    /// Longest side after resizing, in pixels.
    static let maxDimension: CGFloat = 1600

    /// A resized JPEG of the photo. Re-encoding drops the original metadata, including any location.
    static func jpegData(for image: UIImage) -> Data? {
        resized(image).jpegData(compressionQuality: 0.7)
    }

    func save(_ image: UIImage, for occurrenceID: UUID) throws {
        guard let data = Self.jpegData(for: image) else { throw CocoaError(.fileWriteUnknown) }
        try save(data, for: occurrenceID)
    }

    /// Saves JPEG data as it is, e.g. a photo downloaded from the household's cloud storage.
    func save(_ data: Data, for occurrenceID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: occurrenceID), options: .atomic)
    }

    func image(for occurrenceID: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(for: occurrenceID).path(percentEncoded: false))
    }

    func hasPhoto(for occurrenceID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: occurrenceID).path(percentEncoded: false))
    }

    func delete(for occurrenceID: UUID) {
        try? FileManager.default.removeItem(at: url(for: occurrenceID))
    }

    private func url(for occurrenceID: UUID) -> URL {
        directory.appending(path: "\(occurrenceID.uuidString.lowercased()).jpg")
    }

    private static func resized(_ image: UIImage) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
