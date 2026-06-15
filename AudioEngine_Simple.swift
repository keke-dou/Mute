import AVFoundation
import Combine
import UIKit
import MediaPlayer

final class AudioEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    
    @Published var isPlaying = false
    @Published var currentTrackName: String = ""
    @Published var smoothness: Float = 0.5
    @Published var focusVolume: Float = 0.7
    @Published var lowGain: Float = 0.0 { didSet { updateEQ() } }
    @Published var midGain: Float = 0.0 { didSet { updateEQ() } }
    @Published var highGain: Float = 0.0 { didSet { updateEQ() } }
    
    @Published var currentCategory: MusicCategory?
    @Published var playlist: [MusicItem] = []
    @Published var currentIndex: Int = 0

    private var currentAudioFile: AVAudioFile?
    private var isPaused: Bool = false
    
    init() {
        setupAudioSession()
        setupAudioChain()
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    private func setupAudioChain() {
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        
        engine.attach(playerNode)
        engine.attach(eq)

        // Configure EQ bands
        eq.bands[0].filterType = .lowShelf
        eq.bands[0].frequency = 80.0
        eq.bands[0].gain = lowGain
        
        eq.bands[1].filterType = .parametric
        eq.bands[1].frequency = 1000.0
        eq.bands[1].gain = midGain
        
        eq.bands[2].filterType = .highShelf
        eq.bands[2].frequency = 8000.0
        eq.bands[2].gain = highGain

        // Connect: playerNode -> eq -> mainMixer
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: mainMixer, format: format)
    }

    func switchCategory(_ category: MusicCategory, items: [MusicItem]) {
        stop()
        currentCategory = category
        playlist = items
        currentIndex = 0
        playCurrentItem()
    }

    private func playCurrentItem() {
        guard currentIndex >= 0 && currentIndex < playlist.count else { 
            print("playCurrentItem: invalid index")
            return 
        }

        let item = playlist[currentIndex]
        print("playCurrentItem: \(item.name)")

        var fileURL: URL? = nil
        
        // Find the file
        if item.isBuiltIn, let bundleName = item.bundleName {
            fileURL = Bundle.main.url(forResource: bundleName, withExtension: "mp3") ??
                      Bundle.main.url(forResource: bundleName, withExtension: "wav")
        } else if let localName = item.localFileName {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            fileURL = documentsURL.appendingPathComponent(localName)
        }
        
        guard let url = fileURL else {
            print("ERROR: file not found for \(item.name)")
            return
        }

        // Load the file
        do {
            currentAudioFile = try AVAudioFile(forReading: url)
            currentTrackName = item.name
            play()
        } catch {
            print("ERROR loading file: \(error)")
        }
    }

    func play() {
        guard let audioFile = currentAudioFile else {
            print("ERROR: no audio file loaded")
            return
        }

        // Start engine if needed
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("ERROR: failed to start engine: \(error)")
                return
            }
        }

        // Resume from pause
        if isPaused {
            playerNode.play()
            isPlaying = true
            isPaused = false
            return
        }

        // Stop previous playback
        playerNode.stop()
        engine.mainMixerNode.outputVolume = focusVolume

        // Schedule the audio file
        playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.playNextItem()
            }
        }

        // Start playback
        playerNode.play()
        isPlaying = true
        isPaused = false
    }

    private func playNextItem() {
        guard !playlist.isEmpty else { return }
        
        // Move to next track
        currentIndex = (currentIndex + 1) % playlist.count
        playCurrentItem()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        isPaused = true
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        isPaused = false
        currentAudioFile = nil
    }

    func updateEQ() {
        guard eq.bands.count >= 3 else { return }
        eq.bands[0].gain = lowGain
        eq.bands[1].gain = midGain
        eq.bands[2].gain = highGain
    }
    
    deinit {
        engine.stop()
    }
}
