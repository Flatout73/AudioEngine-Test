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
    private var isLoading = false

    @ViewBuilder
    var main: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 32) {
                    if let avAsset = engine.avAsset {
                        VideoPlayer(player: AVPlayer(playerItem: AVPlayerItem(asset: avAsset)))
                            .frame(height: 400)
                    }
                    
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .videos,
                        photoLibrary: .shared()) {
                            Text("Select a video")
                        }
                    
                    if let urlAsset = engine.avAsset {
                        VStack(spacing: 16) {
                            Button("Child filter") {
                                isLoading = true
                                Task {
                                    let filteredAudio = try await engine.saveFilter1Sound()
                                    try await engine.replaceAudioFromVideo(urlAsset.url,
                                                                           with: AVURLAsset(url: filteredAudio))
                                    await MainActor.run {
                                        isLoading = false
                                    }
                                }
                            }
                            Button("Man filter") {
                                isLoading = true
                                Task {
                                    let filteredAudio = try await engine.saveFilter2Sound()
                                    try await engine.replaceAudioFromVideo(urlAsset.url,
                                                                           with: AVURLAsset(url: filteredAudio))
                                    await MainActor.run {
                                        isLoading = false
                                    }
                                }
                            }
                            Button("Alien filter") {
                                isLoading = true
                                Task {
                                    let filteredAudio = try await engine.saveFilter3Sound()
                                    try await engine.replaceAudioFromVideo(urlAsset.url,
                                                                           with: AVURLAsset(url: filteredAudio))
                                    await MainActor.run {
                                        isLoading = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if isLoading {
                ProgressView()
            }
        }
    }

    var body: some View {
        main
        .onChange(of: selectedItem) { newItem in
            isLoading = true
            Task {
                guard let localID = newItem?.itemIdentifier,
                      let result = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject
                else { return }
                try await engine.requestAVAsset(for: result)
                if let asset = engine.avAsset {
                    try await engine.extractAudio(from: asset)
                }
                await MainActor.run {
                    isLoading = false
                }
            }
        }
        .onAppear {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .default)
                try audioSession.setActive(true)
            } catch {
                print(error)
            }
        }
        .toolbar {
            if let urlAsset = engine.avAsset {
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
