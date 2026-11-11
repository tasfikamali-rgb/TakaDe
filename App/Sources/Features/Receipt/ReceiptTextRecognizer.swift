import CoreGraphics
import Vision

/// On-device text recognition with Apple Vision. The image never leaves the phone and
/// is not stored.
enum ReceiptTextRecognizer {
    static func lines(in images: [CGImage]) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            var all: [String] = []
            for image in images {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: image)
                try handler.perform([request])
                let observations = request.results ?? []
                // Top to bottom, so totals come after items like on paper.
                let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                all += sorted.compactMap { $0.topCandidates(1).first?.string }
            }
            return all
        }.value
    }
}
