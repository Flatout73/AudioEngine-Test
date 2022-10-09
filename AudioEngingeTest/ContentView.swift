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

            Button("play") {
                try! engine.play(url: Bundle.main.url(forResource: "Voice", withExtension: "m4a")!)
            }
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                // Retrive selected asset in the form of Data

                if let localID = newItem?.itemIdentifier,
                   let result = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject {
                    avAsset = try await engine.requestAVAsset(for: result)
                    let audioURL = try await engine.extractAudio(from: avAsset!)

                    try engine.play(url: audioURL!)

                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
