// Finalize an App Store preview video with system frameworks only (no ffmpeg):
// scale to an exact WxH, speed up to fit a max duration, normalize to 30 fps,
// add a silent AAC audio track (App Store rejects previews with no/!supported
// audio), and write H.264 MP4.
//
// Usage: swift finalize_preview.swift <input.mov> <output.mp4> <W> <H> <maxSeconds>
import AVFoundation
import CoreMedia

let a = CommandLine.arguments
guard a.count == 6, let W = Int(a[3]), let H = Int(a[4]), let maxSeconds = Double(a[5]) else {
    FileHandle.standardError.write(Data("usage: finalize_preview.swift input output W H maxSeconds\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: a[1])
let output = URL(fileURLWithPath: a[2])

func fail(_ m: String) -> Never {
    FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1)
}

/// Write a silent AAC .m4a of the given length (so the preview has a valid,
/// supported audio track — App Store requires one).
func writeSilentAudio(to url: URL, seconds: Double) throws {
    let sampleRate = 44100.0
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let fmt = file.processingFormat
    var remaining = AVAudioFrameCount(sampleRate * seconds)
    let chunk: AVAudioFrameCount = 44100
    while remaining > 0 {
        let n = min(chunk, remaining)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { break }
        buf.frameLength = n
        if let ch = buf.floatChannelData {
            for c in 0..<Int(fmt.channelCount) { memset(ch[c], 0, Int(n) * MemoryLayout<Float>.size) }
        }
        try file.write(from: buf)
        remaining -= n
    }
}

let asset = AVURLAsset(url: input)
guard let src = asset.tracks(withMediaType: .video).first else { fail("no video track") }
let dur = asset.duration

let comp = AVMutableComposition()
guard let ctrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
    fail("video track error")
}
do { try ctrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: .zero) }
catch { fail("insert error: \(error)") }

// Speed up (scale the time range) so the clip fits maxSeconds.
let targetSec = min(dur.seconds, maxSeconds)
let scaledDur = CMTime(seconds: targetSec, preferredTimescale: 600)
if targetSec < dur.seconds {
    ctrack.scaleTimeRange(CMTimeRange(start: .zero, duration: dur), toDuration: scaledDur)
}

// Silent audio track for the final length.
let silentURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("ts-silent-\(ProcessInfo.processInfo.processIdentifier).m4a")
defer { try? FileManager.default.removeItem(at: silentURL) }
do {
    try writeSilentAudio(to: silentURL, seconds: targetSec + 0.5)
    let silent = AVURLAsset(url: silentURL)
    if let aSrc = silent.tracks(withMediaType: .audio).first,
       let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: scaledDur), of: aSrc, at: .zero)
    }
} catch { fail("silent audio error: \(error)") }

// Scale the frame to exactly WxH (App Store wants a precise size).
let pf = src.preferredTransform
let oriented = src.naturalSize.applying(pf)
let srcW = abs(oriented.width), srcH = abs(oriented.height)
let sx = CGFloat(W) / srcW, sy = CGFloat(H) / srcH

let vc = AVMutableVideoComposition()
vc.renderSize = CGSize(width: W, height: H)
vc.frameDuration = CMTime(value: 1, timescale: 30)
let inst = AVMutableVideoCompositionInstruction()
inst.timeRange = CMTimeRange(start: .zero, duration: scaledDur)
let li = AVMutableVideoCompositionLayerInstruction(assetTrack: ctrack)
li.setTransform(pf.concatenating(CGAffineTransform(scaleX: sx, y: sy)), at: .zero)
inst.layerInstructions = [li]
vc.instructions = [inst]

// Export H.264 MP4 (AAC audio comes from the composition's audio track).
guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
    fail("export session init failed")
}
ex.outputURL = output
ex.outputFileType = .mp4
ex.videoComposition = vc
ex.shouldOptimizeForNetworkUse = true
try? FileManager.default.removeItem(at: output)

let sem = DispatchSemaphore(value: 0)
ex.exportAsynchronously { sem.signal() }
sem.wait()

if ex.status == .completed {
    print(String(format: "ok %dx%d %.1fs +audio", W, H, targetSec))
} else {
    fail("export failed: \(ex.error?.localizedDescription ?? "unknown")")
}
