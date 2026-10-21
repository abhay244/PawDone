// Builds the YouTube Shorts in output/: vertical 1080x1920 videos with captions, a voiceover
// (macOS text-to-speech) and background music.
//
// Usage, from this folder:
//   python3 make-music.py music.wav 60
//   swift make-shorts.swift <clips folder> music.wav
//
// The clips are simulator recordings of the screenshot demo (see README.md). Scripts and
// captions are set in `shorts` below.

import AVFoundation
import AppKit
import VideoToolbox

// MARK: - Scripts

enum Part {
    /// A full-screen title.
    case card(String, voice: String)
    /// Parts of a recording, joined, shown in a phone with a caption above.
    case clip(String, ranges: [(Double, Double)], caption: String, voice: String)
    /// The app icon, name and "Free on the App Store".
    case end(voice: String)
}

struct Short {
    let name: String
    let parts: [Part]
}

let endVoice = "Tail Tick. Free on the App Store."

let shorts = [
    Short(name: "1-who-fed-the-dog", parts: [
        .card("Who fed\nthe dog? 🐶",
              voice: "Who fed the dog? If more than one person looks after your pet, you've asked this before."),
        .clip("today", ranges: [(0, 3)], caption: "Your pet's whole day,\nin one list",
              voice: "Tail Tick puts your pet's whole day in one list, and shows who did each task."),
        .clip("tick-walk", ranges: [(0, 1.6), (12.6, 15.2)], caption: "Done? Tick it off",
              voice: "Back from the walk? Tick it off, with a photo or a note."),
        .clip("notify-done", ranges: [(0, 5)], caption: "Everyone gets notified",
              voice: "Everyone at home gets a notification, so nobody feeds him twice."),
        .clip("family", ranges: [(0, 4)], caption: "Share it with family\nand sitters",
              voice: "Invite your family or pet sitter, and share the care."),
        .end(voice: endVoice),
    ]),
    Short(name: "2-never-miss-the-meds", parts: [
        .card("Never miss your\npet's medicine 💊",
              voice: "Does your pet need medicine every day? Here's how to never miss a dose."),
        .clip("schedule", ranges: [(0, 6.6)], caption: "Add it to the\nschedule once",
              voice: "Add it to the schedule once, with a time, a reminder, and instructions for whoever gives it."),
        .clip("notify-due", ranges: [(0.6, 5.5)], caption: "A reminder when\nit's due",
              voice: "When it's due, Tail Tick reminds you."),
        .clip("tick-supp", ranges: [(0, 2.6), (6.6, 9.6)], caption: "Tick it off",
              voice: "Tick it off, and everyone at home knows it's been given."),
        .end(voice: endVoice),
    ]),
    Short(name: "3-did-the-sitter-do-it", parts: [
        .card("Did the pet sitter\ndo everything? 🐾",
              voice: "Away from home, and wondering if the pet sitter did everything?"),
        .clip("today", ranges: [(0, 3)], caption: "See what's done,\nand who did it",
              voice: "With Tail Tick, your sitter ticks off each task, and you see who did what, and when."),
        .clip("reports", ranges: [(0, 2.0), (4.4, 8.0)], caption: "See what was missed",
              voice: "Reports show every day of the month: what was done, and what was missed."),
        .clip("family", ranges: [(0, 4)], caption: "Helpers can't change\nthe schedule",
              voice: "Helpers can tick tasks off, but only you can change the schedule."),
        .end(voice: endVoice),
    ]),
]

// MARK: - Settings

let size = CGSize(width: 1080, height: 1920)
let fps: Int32 = 30
let voiceName = "Samantha"
let voiceRate = "180"
let musicVolume: Float = 0.18
let topColor = CGColor(srgbRed: 0.957, green: 0.357, blue: 0.310, alpha: 1)    // #F45B4F
let bottomColor = CGColor(srgbRed: 1.0, green: 0.541, blue: 0.396, alpha: 1)   // #FF8A65
let coral = NSColor(srgbRed: 1.0, green: 0.431, blue: 0.365, alpha: 1)         // #FF6E5D

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: swift make-shorts.swift <clips folder> <music.wav>")
    exit(1)
}
let clipsFolder = URL(fileURLWithPath: args[1])
let musicURL = URL(fileURLWithPath: args[2])
let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputFolder = here.appendingPathComponent("output")
let workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("tailtick-shorts")
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)

// MARK: - Drawing helpers

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    guard let rounded = font.fontDescriptor.withDesign(.rounded) else { return font }
    return NSFont(descriptor: rounded, size: size) ?? font
}

/// Draws centred text into a transparent image as wide as the video.
func textImage(_ text: String, font: NSFont, color: NSColor, lineHeight: CGFloat = 1.05) -> CGImage {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = lineHeight
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    let width = size.width - 120
    let height = ceil(string.boundingRect(with: CGSize(width: width, height: 2000), options: .usesLineFragmentOrigin).height) + 20
    let context = makeContext(Int(size.width), Int(height))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    string.draw(with: CGRect(x: 60, y: 10, width: width, height: height - 20), options: .usesLineFragmentOrigin)
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

let background: CGImage = {
    let context = makeContext(Int(size.width), Int(size.height))
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottomColor, topColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    return context.makeImage()!
}()

let appIcon: CGImage = {
    let url = here.deletingLastPathComponent().appendingPathComponent("TailTick-AppIcon-1024.png")
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}()

func ease(_ x: Double) -> Double { let t = min(max(x, 0), 1); return 1 - pow(1 - t, 3) }

/// Draws `image` with its top at `top` (from the top of the frame), centred, scaled and faded.
func draw(_ image: CGImage, in context: CGContext, top: CGFloat, scale: CGFloat = 1, alpha: CGFloat = 1, centerX: CGFloat? = nil) {
    let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
    let x = (centerX ?? size.width / 2) - w / 2
    context.saveGState()
    context.setAlpha(alpha)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: x, y: size.height - top - h, width: w, height: h))
    context.restoreGState()
}

// MARK: - Reading recordings

/// Hands out the frame showing at a given time in a recording made of joined ranges.
final class ClipReader {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let ranges: [(Double, Double)]
    let length: Double
    private var rangeIndex = -1
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var current: CGImage?
    private var pending: (time: Double, image: CGImage)?

    init(url: URL, ranges: [(Double, Double)]) async throws {
        asset = AVURLAsset(url: url)
        track = try await asset.loadTracks(withMediaType: .video).first!
        let duration = try await asset.load(.duration).seconds
        self.ranges = ranges.map { ($0.0, min($0.1, duration)) }
        length = self.ranges.reduce(0) { $0 + ($1.1 - $1.0) }
    }

    func frame(at time: Double) throws -> CGImage? {
        var remaining = min(max(time, 0), length - 0.001)
        var index = 0
        while index < ranges.count - 1, remaining > ranges[index].1 - ranges[index].0 {
            remaining -= ranges[index].1 - ranges[index].0
            index += 1
        }
        if index != rangeIndex { try open(index) }
        let target = ranges[index].0 + remaining
        while true {
            if let next = pending {
                guard next.time <= target else { break }
                current = next.image
                pending = nil
            }
            guard let sample = output?.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) else { break }
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            if let image { pending = (CMSampleBufferGetPresentationTimeStamp(sample).seconds, image) }
        }
        return current
    }

    private func open(_ index: Int) throws {
        reader?.cancelReading()
        let reader = try AVAssetReader(asset: asset)
        let (start, end) = ranges[index]
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       end: CMTime(seconds: end, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        reader.startReading()
        self.reader = reader
        self.output = output
        rangeIndex = index
        pending = nil
    }
}

// MARK: - Voiceover

func speak(_ text: String, to url: URL) throws -> Double {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-v", voiceName, "-r", voiceRate, "-o", url.path, text]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "say", code: Int(process.terminationStatus)) }
    let file = try AVAudioFile(forReading: url)
    return Double(file.length) / file.fileFormat.sampleRate
}

// MARK: - Building one Short

struct Segment {
    let part: Part
    let start: Double
    let duration: Double
    let voiceURL: URL
    let voiceStart: Double
    let reader: ClipReader?
    let speed: Double
    let overlay: CGImage?
}

func build(_ short: Short) async throws {
    print("\(short.name):")
    // Lay out the timeline from the voiceover lengths.
    var segments: [Segment] = []
    var time = 0.0
    for (index, part) in short.parts.enumerated() {
        let voiceURL = workFolder.appendingPathComponent("\(short.name)-\(index).aiff")
        switch part {
        case let .card(title, voice):
            let length = try speak(voice, to: voiceURL)
            let duration = max(length + 0.7, 2.4)
            let overlay = textImage(title, font: roundedFont(118, .heavy), color: .white)
            segments.append(Segment(part: part, start: time, duration: duration, voiceURL: voiceURL,
                                    voiceStart: time + 0.25, reader: nil, speed: 1, overlay: overlay))
            time += duration
        case let .clip(name, ranges, caption, voice):
            let length = try speak(voice, to: voiceURL)
            let reader = try await ClipReader(url: clipsFolder.appendingPathComponent("\(name).mp4"), ranges: ranges)
            // Long enough for the voice; recordings longer than that play faster (up to 2x).
            let duration = max(length + 0.7, reader.length / 2, 2.5)
            let speed = max(1, reader.length / duration)
            let overlay = textImage(caption, font: roundedFont(70, .bold), color: .white)
            segments.append(Segment(part: part, start: time, duration: duration, voiceURL: voiceURL,
                                    voiceStart: time + 0.3, reader: reader, speed: speed, overlay: overlay))
            time += duration
        case let .end(voice):
            let length = try speak(voice, to: voiceURL)
            let duration = length + 1.6
            segments.append(Segment(part: part, start: time, duration: duration, voiceURL: voiceURL,
                                    voiceStart: time + 0.35, reader: nil, speed: 1, overlay: nil))
            time += duration
        }
    }
    let total = time
    print(String(format: "  %.1f seconds, %d parts", total, segments.count))

    // Video.
    let videoURL = workFolder.appendingPathComponent("\(short.name)-video.mp4")
    try? FileManager.default.removeItem(at: videoURL)
    let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(size.width),
        AVVideoHeightKey: Int(size.height),
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 10_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let endTitle = textImage("TailTick", font: roundedFont(132, .heavy), color: .white)
    let endTagline = textImage("Your pet's day, shared", font: roundedFont(58, .semibold), color: NSColor.white.withAlphaComponent(0.92))
    let endSearch = textImage("Search TailTick", font: roundedFont(46, .medium), color: NSColor.white.withAlphaComponent(0.9))
    let endBadge = textImage("Free on the App Store", font: roundedFont(54, .bold), color: coral)

    let frameCount = Int(ceil(total * Double(fps)))
    for frameIndex in 0..<frameCount {
        let t = Double(frameIndex) / Double(fps)
        let segment = segments.last { $0.start <= t } ?? segments[0]
        let local = t - segment.start

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
        guard let pixelBuffer else { fatalError("No pixel buffer") }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.draw(background, in: CGRect(origin: .zero, size: size))
        let appear = ease(local / 0.4)

        switch segment.part {
        case .card:
            let title = segment.overlay!
            // Visible from the first frame: it's the hook, and often the thumbnail.
            draw(title, in: context, top: (size.height - CGFloat(title.height)) / 2 - 60,
                 scale: 0.94 + 0.06 * appear)

        case .clip:
            let caption = segment.overlay!
            draw(caption, in: context, top: 150 + 30 * (1 - appear), alpha: appear)
            // The phone, gently zooming in.
            let phoneHeight: CGFloat = 1440, phoneTop: CGFloat = 400
            let zoom = 1 + 0.025 * local / segment.duration
            let screen = CGSize(width: phoneHeight * 1320 / 2868 * zoom, height: phoneHeight * zoom)
            let rect = CGRect(x: (size.width - screen.width) / 2, y: size.height - phoneTop - phoneHeight - (screen.height - phoneHeight) / 2,
                              width: screen.width, height: screen.height)
            let radius = 95 * zoom, bezel: CGFloat = 13
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: CGColor(gray: 0, alpha: 0.3))
            context.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
            context.addPath(CGPath(roundedRect: rect.insetBy(dx: -bezel, dy: -bezel), cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
            context.fillPath()
            context.restoreGState()
            if let frame = try segment.reader!.frame(at: local * segment.speed) {
                context.saveGState()
                context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.clip()
                context.interpolationQuality = .high
                context.draw(frame, in: rect)
                context.restoreGState()
            }

        case .end:
            let iconSize: CGFloat = 300 * (0.85 + 0.15 * appear)
            let iconRect = CGRect(x: (size.width - iconSize) / 2, y: size.height - 520 - iconSize, width: iconSize, height: iconSize)
            context.saveGState()
            context.setAlpha(appear)
            context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.25))
            context.addPath(CGPath(roundedRect: iconRect, cornerWidth: iconSize * 0.225, cornerHeight: iconSize * 0.225, transform: nil))
            context.clip()
            context.draw(appIcon, in: iconRect)
            context.restoreGState()
            let later = ease((local - 0.25) / 0.4)
            draw(endTitle, in: context, top: 860, alpha: later)
            draw(endTagline, in: context, top: 1030, alpha: later)
            // A white pill with "Free on the App Store".
            let pill = CGRect(x: (size.width - 660) / 2, y: size.height - 1170 - 120, width: 660, height: 120)
            context.saveGState()
            context.setAlpha(ease((local - 0.5) / 0.4))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.addPath(CGPath(roundedRect: pill, cornerWidth: 60, cornerHeight: 60, transform: nil))
            context.fillPath()
            context.restoreGState()
            draw(endBadge, in: context, top: 1170 + (120 - CGFloat(endBadge.height)) / 2, alpha: ease((local - 0.5) / 0.4))
            draw(endSearch, in: context, top: 1340, alpha: ease((local - 0.7) / 0.4))
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: fps))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "writer", code: 1) }

    // Audio: the voiceover over the music, then export.
    let composition = AVMutableComposition()
    let duration = CMTime(seconds: total, preferredTimescale: 600)
    let video = AVURLAsset(url: videoURL)
    let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                   of: try await video.loadTracks(withMediaType: .video).first!, at: .zero)
    let voiceTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    for segment in segments {
        let voice = AVURLAsset(url: segment.voiceURL)
        let source = try await voice.loadTracks(withMediaType: .audio).first!
        let length = try await voice.load(.duration)
        try voiceTrack.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source,
                                       at: CMTime(seconds: segment.voiceStart, preferredTimescale: 600))
    }
    let music = AVURLAsset(url: musicURL)
    let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try musicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                   of: try await music.loadTracks(withMediaType: .audio).first!, at: .zero)
    let musicMix = AVMutableAudioMixInputParameters(track: musicTrack)
    musicMix.setVolume(musicVolume, at: .zero)
    musicMix.setVolumeRamp(fromStartVolume: musicVolume, toEndVolume: 0,
                           timeRange: CMTimeRange(start: CMTime(seconds: total - 1.2, preferredTimescale: 600),
                                                  duration: CMTime(seconds: 1.2, preferredTimescale: 600)))
    let audioMix = AVMutableAudioMix()
    audioMix.inputParameters = [musicMix]

    let outputURL = outputFolder.appendingPathComponent("\(short.name).mp4")
    try? FileManager.default.removeItem(at: outputURL)
    let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
    export.audioMix = audioMix
    try await export.export(to: outputURL, as: .mp4)
    print("  wrote output/\(short.name).mp4")
}

for short in shorts {
    try await build(short)
}
