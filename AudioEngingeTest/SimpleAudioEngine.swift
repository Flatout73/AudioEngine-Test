//
//  SimpleAudioEngine.swift
//  AudioEngingeTest
//
//  Created by Leonid Lyadveykin on 09.10.2022.
//

import Foundation
import AVFoundation
import PhotosUI

enum EngineError: Error {
    case loading
    case extracting
    case filtering
    case rendering
}

class SimpleAudioEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private let speedControl = AVAudioUnitVarispeed()
    private let pitchControl = AVAudioUnitTimePitch()

    private let audioPlayer = AVAudioPlayerNode()

    @Published
    var avAsset: AVURLAsset?

    var audioURL: URL?

    private lazy var tempDir = FileManager.default.urls(for: .cachesDirectory, in: .allDomainsMask)[0]

    private var outref: ExtAudioFileRef?

    init() {
        engine.attach(audioPlayer)
        engine.attach(speedControl)
        engine.attach(pitchControl)

        engine.connect(audioPlayer, to: speedControl, format: nil)
        engine.connect(speedControl, to: pitchControl, format: nil)
        engine.connect(pitchControl, to: engine.mainMixerNode, format: nil)
    }

    func saveFilter1Sound() async throws -> URL {
        guard let audioURL else { throw EngineError.filtering }
        pitchControl.pitch = 1000
        speedControl.rate = 1.1
        return try saveSound(from: audioURL)
    }

    func saveFilter2Sound() async throws -> URL {
        guard let audioURL else { throw EngineError.filtering }
        pitchControl.pitch = 100
        speedControl.rate = 0.9
        return try saveSound(from: audioURL)
    }

    func requestAVAsset(for asset: PHAsset) async throws {
        let asset = try await withCheckedThrowingContinuation { promise in
            PHCachingImageManager().requestAVAsset(forVideo: asset, options: nil) { avAsset, _, _ in
                if let avAsset {
                    promise.resume(returning: avAsset)
                } else {
                    promise.resume(throwing: EngineError.loading)
                }
            }
        }
        
        await MainActor.run {
            self.avAsset = asset as? AVURLAsset
        }
    }

    func extractAudio(from asset: AVAsset) async throws {
        // Create a composition
        let composition = AVMutableComposition()
        do {
            for audioAssetTrack in try await asset.loadTracks(withMediaType: AVMediaType.audio) {
                guard let audioCompositionTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                              preferredTrackID: kCMPersistentTrackID_Invalid)
                else {
                    throw EngineError.extracting
                }
                try await audioCompositionTrack.insertTimeRange(audioAssetTrack.load(.timeRange),
                                                                of: audioAssetTrack,
                                                                at: audioAssetTrack.load(.timeRange).start)
            }
        } catch {
            throw EngineError.extracting
        }

        // Get url for output
        let outputUrl = URL(fileURLWithPath: tempDir.appending(path: "out.m4a").path())
        if FileManager.default.fileExists(atPath: outputUrl.path) {
            try FileManager.default.removeItem(atPath: outputUrl.path)
        }

        // Create an export session
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)!
        exportSession.outputFileType = AVFileType.m4a
        exportSession.outputURL = outputUrl

        // Export file
        await exportSession.export()
        //guard case exportSession.status = AVAssetExportSession.Status.completed else { return nil }

        self.audioURL = outputUrl
    }

    private func saveSound(from url: URL) throws -> URL {
        engine.reset()
        let file = try AVAudioFile(forReading: url)

        audioPlayer.scheduleFile(file, at: nil, completionHandler: nil)

        let filteredAudioFilePath = tempDir.appending(path: "filteredAudio.m4a")
        if FileManager.default.fileExists(atPath: filteredAudioFilePath.path) {
            try FileManager.default.removeItem(atPath: filteredAudioFilePath.path)
        }

        let maxFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: file.processingFormat,
                                             maximumFrameCount: maxFrames)

        try engine.start()
        audioPlayer.play()

        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                      frameCapacity: engine.manualRenderingMaximumFrameCount)!

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(forWriting: filteredAudioFilePath, settings: file.fileFormat.settings)
        } catch {
            print("Unable to open output audio file: \(error).")
            throw EngineError.rendering
        }

        while engine.manualRenderingSampleTime < file.length {
            do {
                let frameCount = file.length - engine.manualRenderingSampleTime
                let framesToRender = min(AVAudioFrameCount(frameCount), buffer.frameCapacity)

                let status = try engine.renderOffline(framesToRender, to: buffer)

                switch status {
                case .success:
                    // The data rendered successfully. Write it to the output file.
                    try outputFile.write(from: buffer)
                case .insufficientDataFromInputNode:
                    // Applicable only when using the input node as one of the sources.
                    break
                case .cannotDoInCurrentContext:
                    // The engine couldn't render in the current render call.
                    // Retry in the next iteration.
                    break
                default:
                    // An error occurred while rendering the audio.
                    print("The manual rendering failed.")
                    throw EngineError.rendering
                }
            } catch {
                print("The manual rendering failed: \(error).")
                throw EngineError.rendering
            }
        }

        // Stop the player node and engine.
        audioPlayer.stop()
        engine.stop()

        return filteredAudioFilePath
    }

    func replaceAudioFromVideo(_ videoURL: URL, with audio: AVAsset) async throws {
        let inputVideoURL: URL = videoURL
        let sourceAsset = AVURLAsset(url: inputVideoURL)
        let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: AVMediaType.video)[0]
        let sourceAudioTrack = try await audio.loadTracks(withMediaType: .audio)[0]

        let composition = AVMutableComposition()
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video,
                                                                preferredTrackID: kCMPersistentTrackID_Invalid)
        let x: CMTimeRange = CMTimeRangeMake(start: CMTime.zero, duration: sourceAsset.duration)
        _ = try compositionVideoTrack?.insertTimeRange(x, of: sourceVideoTrack, at: CMTime.zero)

        let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        _ = try compositionAudioTrack?.insertTimeRange(x, of: sourceAudioTrack, at: CMTime.zero)

        let mutableVideoURL = URL(fileURLWithPath: tempDir.appending(path: "finalVideo.mp4").path())
        let exporter: AVAssetExportSession = AVAssetExportSession(asset: composition,
                                                                  presetName: AVAssetExportPresetHighestQuality)!
        exporter.outputFileType = AVFileType.mp4
        exporter.outputURL = mutableVideoURL
        if FileManager.default.fileExists(atPath: mutableVideoURL.path) {
            try? FileManager.default.removeItem(atPath: mutableVideoURL.path)
        }

        await exporter.export()

        await MainActor.run {
            self.avAsset = AVURLAsset(url: mutableVideoURL)
        }
    }
}
