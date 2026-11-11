import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import ImageIO
import PDFKit
import Vision
import Photos
import CoreTransferable

/// A picked video copied into a temp file (avoids loading huge videos into memory).
struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return MovieFile(url: dst)
        }
    }
}

enum MediaTools {
    static func kind(for url: URL) -> VaultFileKind {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .document }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        return .document
    }

    static func thumbnail(for url: URL, kind: VaultFileKind, maxPixel: CGFloat = 360) async -> Data? {
        switch kind {
        case .image:
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceThumbnailMaxPixelSize: maxPixel]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
        case .video:
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            guard let result = try? await gen.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) else { return nil }
            return UIImage(cgImage: result.image).jpegData(compressionQuality: 0.7)
        case .pdf, .scan:
            guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: maxPixel, height: maxPixel), for: .mediaBox).jpegData(compressionQuality: 0.7)
        case .document:
            return nil
        }
    }

    static func pdf(from images: [UIImage]) -> Data {
        let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: a4)
        return renderer.pdfData { ctx in
            for img in images {
                ctx.beginPage()
                let s = min(a4.width / img.size.width, a4.height / img.size.height)
                let w = img.size.width * s, h = img.size.height * s
                img.draw(in: CGRect(x: (a4.width - w) / 2, y: (a4.height - h) / 2, width: w, height: h))
            }
        }
    }

    /// On-device OCR (Arabic + English when supported).
    static func recognizeText(_ images: [UIImage]) async -> String {
        await Task.detached(priority: .userInitiated) {
            var parts: [String] = []
            for img in images {
                guard let cg = img.cgImage else { continue }
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = true
                if let supported = try? req.supportedRecognitionLanguages() {
                    let wanted = ["ar-SA", "ars-SA", "en-US"].filter { supported.contains($0) }
                    if !wanted.isEmpty { req.recognitionLanguages = wanted }
                }
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
                let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                parts.append(text)
            }
            return parts.joined(separator: "\n\n")
        }.value
    }

    static func deleteFromPhotos(_ identifiers: [String]) async -> Bool {
        guard !identifiers.isEmpty else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            return false
        }
    }
}

/// Silently grabs one frame from the front camera (no shutter sound) to photograph intruders.
final class IntruderCam: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = IntruderCam()

    private let queue = DispatchQueue(label: "ayn.intruder.cam")
    private var session: AVCaptureSession?
    private var completion: ((Data?) -> Void)?
    private var started = Date()
    private var finished = true

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sec.intruder") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sec.intruder") }
    }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func capture(_ done: @escaping (Data?) -> Void) {
        guard Self.enabled, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { done(nil); return }
        queue.async {
            guard self.finished else { done(nil); return }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device) else { done(nil); return }
            let s = AVCaptureSession()
            // Full 4:3 sensor frame (no crop) so the whole face and surroundings are visible.
            s.sessionPreset = s.canSetSessionPreset(.photo) ? .photo : .high
            guard s.canAddInput(input) else { done(nil); return }
            s.addInput(input)
            let out = AVCaptureVideoDataOutput()
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: self.queue)
            guard s.canAddOutput(out) else { done(nil); return }
            s.addOutput(out)
            if let c = out.connection(with: .video), c.isVideoRotationAngleSupported(90) {
                c.videoRotationAngle = 90
            }
            self.completion = done
            self.finished = false
            self.session = s
            self.started = Date()
            s.startRunning()
            self.queue.asyncAfter(deadline: .now() + 4) { self.finish(nil) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !finished, Date().timeIntervalSince(started) > 0.8,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var ci = CIImage(cvPixelBuffer: pb).oriented(.upMirrored)
        let longSide = max(ci.extent.width, ci.extent.height)
        if longSide > 1600 {
            let k = 1600 / longSide
            ci = ci.transformed(by: CGAffineTransform(scaleX: k, y: k))
        }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        finish(UIImage(cgImage: cg).jpegData(compressionQuality: 0.8))
    }

    private func finish(_ data: Data?) {
        guard !finished else { return }
        finished = true
        session?.stopRunning()
        session = nil
        let c = completion
        completion = nil
        DispatchQueue.main.async { c?(data) }
    }
}
