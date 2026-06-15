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
    @Published var focusVolume: Float = 0.7
    // 音乐能量 - 由播放状态和音量驱动，供艺术引擎使用
    @Published var musicEnergy: Float = 0.0
    @Published var musicBeat: Float = 0.0
    @Published var lowGain: Float = 0.0 {
        didSet { updateEQBand(0) }
    }
    @Published var midGain: Float = 0.0 {
        didSet { updateEQBand(1) }
    }
    @Published var highGain: Float = 0.0 {
        didSet { updateEQBand(2) }
    }
    @Published var smoothness: Float = 0.5
    
    @Published var currentCategory: MusicCategory?
    @Published var playlist: [MusicItem] = []
    @Published var currentIndex: Int = 0
    private var isSequentialMode: Bool = true
    
    private var currentAudioFile: AVAudioFile?
    private var isPaused: Bool = false
    
    init() {
        setupAudioSession()
        setupAudioChain()
        startEngine()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [
                .mixWithOthers,
                .allowAirPlay,
                .allowBluetooth,
                .allowBluetoothA2DP
            ])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 监听中断
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption(_:)),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            
            // 监听路由变化
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioRouteChange(_:)),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
            
            // 监听应用生命周期
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppDidEnterBackground(_:)),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppWillEnterForeground(_:)),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
            
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // 中断开始，暂停播放
            if isPlaying {
                pause()
            }
        case .ended:
            // 中断结束，尝试恢复
            if let optionValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        // 路由变化时，确保引擎运行
        if isPlaying {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to activate audio session: \(error)")
            }
        }
    }
    
    @objc private func handleAppDidEnterBackground(_ notification: Notification) {
        // 进入后台时保持音频会话活跃
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to keep audio session active: \(error)")
        }
    }
    
    @objc private func handleAppWillEnterForeground(_ notification: Notification) {
        // 回到前台时确保引擎运行
        if isPlaying {
            startEngine()
        }
    }
    
    private func setupAudioChain() {
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        
        engine.attach(playerNode)
        engine.attach(eq)
        
        // 配置 EQ
        // 低频：低通滤波器，80 Hz
        eq.bands[0].filterType = .lowShelf
        eq.bands[0].frequency = 80.0
        eq.bands[0].bandwidth = 0.5  // 降低带宽使调节更平滑
        eq.bands[0].gain = lowGain
        eq.bands[0].bypass = false

        // 中频：参数化滤波器，1 kHz
        eq.bands[1].filterType = .parametric
        eq.bands[1].frequency = 1000.0
        eq.bands[1].bandwidth = 0.5  // 降低带宽使调节更平滑
        eq.bands[1].gain = midGain
        eq.bands[1].bypass = false

        // 高频：高通滤波器，8 kHz
        eq.bands[2].filterType = .highShelf
        eq.bands[2].frequency = 8000.0
        eq.bands[2].bandwidth = 0.5  // 降低带宽使调节更平滑
        eq.bands[2].gain = highGain
        eq.bands[2].bypass = false
        
        // 连接: playerNode -> eq -> mainMixer
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: mainMixer, format: format)
        
        // 应用初始 EQ 设置
        updateEQ()
    }
    
    private func updateEQBand(_ index: Int) {
        guard eq.bands.count > index else { return }
        eq.bands[index].gain = [lowGain, midGain, highGain][index]
    }
    
    func updateEQ() {
        guard eq.bands.count >= 3 else { return }
        eq.bands[0].gain = lowGain
        eq.bands[1].gain = midGain
        eq.bands[2].gain = highGain
        print("EQ updated: L=\(lowGain)dB M=\(midGain)dB H=\(highGain)dB")
    }
    
    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            print("Audio engine started")
        } catch {
            print("Failed to start engine: \(error)")
        }
    }
    
    private func findBundleResource(named name: String, withExtension ext: String) -> URL? {
        // 先尝试直接查找
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        
        // 在子文件夹中查找
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: resourceURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.deletingPathExtension().lastPathComponent == name && fileURL.pathExtension == ext {
                    return fileURL
                }
            }
        }
        
        return nil
    }
    
    private func getFileURL(for item: MusicItem) -> URL? {
        if item.isBuiltIn, let bundleName = item.bundleName {
            return findBundleResource(named: bundleName, withExtension: "mp3") ??
                   findBundleResource(named: bundleName, withExtension: "wav")
        } else if let localName = item.localFileName {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documentsURL.appendingPathComponent(localName)
        }
        return nil
    }
    
    func switchCategory(_ category: MusicCategory, items: [MusicItem]) {
        loadPlaylist(items: items, category: category)
    }
    
    func loadPlaylist(items: [MusicItem], category: MusicCategory) {
        stop()
        
        currentCategory = category
        playlist = items
        // 多首歌时按顺序循环播放
        isSequentialMode = items.count > 1
        currentIndex = 0
        
        playCurrentItem()
    }
    
    private func playCurrentItem() {
        guard currentIndex >= 0 && currentIndex < playlist.count else {
            print("playCurrentItem: invalid index \(currentIndex)")
            return
        }
        
        let item = playlist[currentIndex]
        print("playCurrentItem: loading \(item.name)")
        
        guard let url = getFileURL(for: item) else {
            print("playCurrentItem: no URL for item \(item.name)")
            return
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("playCurrentItem: file not found at \(url.path)")
            return
        }
        
        do {
            currentAudioFile = try AVAudioFile(forReading: url)
            currentTrackName = item.name
            print("playCurrentItem: loaded \(url.lastPathComponent)")
            play()
        } catch {
            print("playCurrentItem: failed to load file: \(error)")
        }
    }
    
    private func playNextItem() {
        guard !playlist.isEmpty else { return }
        
        isPaused = false
        
        if isSequentialMode {
            // 顺序播放
            currentIndex = (currentIndex + 1) % playlist.count
        } else {
            // 单曲循环，不改变索引
        }
        
        playCurrentItem()
    }
    
    func play() {
        guard let audioFile = currentAudioFile else {
            print("play: no audio file loaded")
            return
        }
        
        // 确保引擎运行
        startEngine()
        
        if isPaused {
            // 恢复播放
            playerNode.play()
            isPlaying = true
            isPaused = false
            updateNowPlayingInfo()
            return
        }
        
        // 停止之前的播放
        playerNode.stop()
        engine.mainMixerNode.outputVolume = focusVolume
        
        // 根据播放模式调度
        if playlist.count <= 1 {
            // 单曲：循环播放
            playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    // 单曲循环：重新调度同一文件
                    if let strongSelf = self, strongSelf.currentAudioFile != nil {
                        strongSelf.playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                            DispatchQueue.main.async {
                                if let ss = self, ss.currentAudioFile != nil {
                                    // 继续循环
                                    strongSelf.playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                                        DispatchQueue.main.async {
                                            self?.playNextItem()
                                        }
                                    }
                                    ss.playerNode.play()
                                }
                            }
                        }
                        strongSelf.playerNode.play()
                    }
                }
            }
        } else {
            // 播放列表：播放完切下一首
            playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.playNextItem()
                }
            }
        }
        
        playerNode.play()
        isPlaying = true
        musicEnergy = 0.8  // 播放时能量高
        updateNowPlayingInfo()
        print("play: started playing \(audioFile.url.lastPathComponent)")
    }

    func pause() {
        guard isPlaying else { return }
        playerNode.pause()
        isPlaying = false
        isPaused = true
        musicEnergy = 0.0  // 暂停时无能量
        updateNowPlayingInfo()
    }
    
    func stop() {
        playerNode.stop()
        isPlaying = false
        isPaused = false
        currentAudioFile = nil
        currentTrackName = ""
        musicEnergy = 0.0
        updateNowPlayingInfo()
    }
    
    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyTitle] = currentTrackName
        if let file = currentAudioFile {
            let duration = Double(file.length) / file.processingFormat.sampleRate
            if duration.isFinite && duration > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    deinit {
        engine.stop()
    }
}
