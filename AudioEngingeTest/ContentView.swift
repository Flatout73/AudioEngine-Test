//
//  ContentView.swift
//  AudioEngingeTest
//
//  Created by Leonid Lyadveykin on 09.10.2022.
//

import SwiftUI
import PhotosUI
import AVKit

struct ContentView: View {
    @StateObject
    var engine = SimpleAudioEngine()

    @State
    private var selectedItem: PhotosPickerItem? = nil

    @State
    private var avAsset: AVAsset?

    var body: some View {
        VStack {
            if let avAsset {
                VideoPlayer(player: AVPlayer(playerItem: AVPlayerItem(asset: avAsset)))
                    .frame(height: 400)
            }

            PhotosPicker(
                selection: $selectedItem,
                matching: .videos,
                photoLibrary: .shared()) {
                    Text("Select a video")
                }

            if let urlAsset = avAsset as? AVURLAsset {
                Button("Filter") {
                    Task {
                        let audioURL = try await engine.extractAudio(from: urlAsset)
                        let filteredAudio = try engine.saveSound(from: audioURL)

                        let newVideoURL = try await engine.replaceAudioFromVideo(urlAsset.url,
                                                                                 with: AVURLAsset(url: filteredAudio))
                        avAsset = AVURLAsset(url: newVideoURL)
                    }
                }
            }
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                // Retrive selected asset in the form of Data

                if let localID = newItem?.itemIdentifier,
                   let result = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject {
                    avAsset = try await engine.requestAVAsset(for: result)
                }
            }
        }
        .onAppear {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, options: .defaultToSpeaker)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                print(error)
            }
        }
        .toolbar {
            if let urlAsset = avAsset as? AVURLAsset {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: urlAsset.url)
                }
            }
        }
        .navigationTitle("Video filters")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
