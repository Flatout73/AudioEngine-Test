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
}

class SimpleAudioEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private let speedControl = AVAudioUnitVarispeed()
    private let pitchControl = AVAudioUnitTimePitch()
    private let mixer = AVAudioMixerNode()

    lazy var tempDir = FileManager.default.urls(for: .cachesDirectory, in: .allDomainsMask)[0]

    func requestAVAsset(for asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { promise in
            PHCachingImageManager().requestAVAsset(forVideo: asset, options: nil) { avAsset, _, _ in
                if let avAsset {
                    promise.resume(returning: avAsset)
                } else {
                    promise.resume(throwing: EngineError.loading)
                }
            }
        }
    }

    func extractAudio(from asset: AVAsset) async throws -> URL? {
        // Create a composition
        let composition = AVMutableComposition()
        do {
            for audioAssetTrack in try await asset.loadTracks(withMediaType: AVMediaType.audio) {
                guard let audioCompositionTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                              preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
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
            try? FileManager.default.removeItem(atPath: outputUrl.path)
        }

        // Create an export session
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)!
        exportSession.outputFileType = AVFileType.m4a
        exportSession.outputURL = outputUrl

        // Export file
        await exportSession.export()
        //guard case exportSession.status = AVAssetExportSession.Status.completed else { return nil }

        return exportSession.outputURL
    }

    func saveSound(from url: URL) throws {
        let file = try AVAudioFile(forReading: url)

        let audioPlayer = AVAudioPlayerNode()

//        print(eqControl.bands[0].frequency)
//        eqControl.bands[0].filterType = .bandPass
//        eqControl.bands[0].frequency = 1000
//        //eqControl.bands[0].bandwidth = 5
//        //eqControl.bands[0].gain = 0
//        eqControl.bands[0].bypass = false
//        print(eqControl.bands[0].frequency)

//        eqControl.loadFactoryPreset(.plate)
//        eqControl.wetDryMix = 0.1

        pitchControl.pitch += 500
        speedControl.rate = 1.1

        engine.attach(audioPlayer)
        engine.attach(speedControl)
        engine.attach(pitchControl)
        engine.attach(mixer)

        engine.connect(audioPlayer, to: speedControl, format: nil)
        engine.connect(speedControl, to: pitchControl, format: nil)
        engine.connect(pitchControl, to: mixer, format: nil)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)

//        _ = ExtAudioFileCreateWithURL(URL(fileURLWithPath: self.filePath!) as CFURL,
//                                              kAudioFileWAVEType,
//                                              (format?.streamDescription)!,
//                                              nil,
//                                              AudioFileFlags.eraseFile.rawValue,
//                                              &outref)

        audioPlayer.scheduleFile(file, at: nil)

        try engine.start()
        audioPlayer.play()
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
    }
}
