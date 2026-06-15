import SwiftUI
import AVFoundation
import SwiftData
import PhotosUI

enum PickerType {
    case file
    case video
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tracks: [Track]

    @StateObject private var timerManager = FocusTimerManager()
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var musicLibrary = MusicLibrary()
    @StateObject private var videoConverter = VideoConverter()

    @State private var showingFilePicker = false
    @State private var showingDurationPicker = false
    @State private var showingMusicSelector = false
    @State private var showingImportOptions = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var isProcessingVideo = false
    @State private var pendingPickerType: PickerType?
    @State private var isEditingImports = false
    @State private var editMode: EditMode = .inactive
    @State private var showingImportSuccess = false
    @State private var lastImportedSongName = ""
    @State private var musicListRefreshId = UUID()
    @State private var isUIVisible: Bool = true

    var body: some View {
        ZStack {
            backgroundGradient

            Color.black.opacity(0.15)
                .ignoresSafeArea()

            // 点击空白区域切换 UI 显示
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isUIVisible.toggle()
                    }
                }

            VStack(spacing: 0) {
                topSliders
                    .padding(.top, 60)
                    .padding(.horizontal, 24)

                Spacer()

                centerContent

                Spacer()
            }
            .opacity(isUIVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: isUIVisible)

            if isProcessingVideo {
                conversionLoadingOverlay
            }
        }
        .onAppear {
            loadFirstTrackIfNeeded()
        }
        .sheet(isPresented: $showingDurationPicker) {
            durationPickerSheet
        }
        .sheet(isPresented: $showingMusicSelector) {
            musicSelectorSheet
        }
        .photosPicker(isPresented: $showingImportOptions, selection: $selectedVideoItem, matching: .videos)
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let newItem = newItem else { return }
            handleVideoSelection(newItem)
        }
        .onChange(of: showingMusicSelector) { _, isShowing in
            if !isShowing, let pickerType = pendingPickerType {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    switch pickerType {
                    case .file:
                        self.showingFilePicker = true
                    case .video:
                        self.showingImportOptions = true
                    }
                    self.pendingPickerType = nil
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert("导入成功", isPresented: $showingImportSuccess) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("\(lastImportedSongName) 已添加到我的导入！")
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundGradient: some View {
        ZStack {
            // 根据系统暗/亮模式显示不同背景
            Group {
                if colorScheme == .dark {
                    // 暗模式：纯黑色背景
                    Color.black
                } else {
                    // 亮模式：当前的渐变背景
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.5),
                            Color.indigo.opacity(0.3),
                            Color.purple.opacity(0.2),
                            Color.black.opacity(0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }

            if timerManager.isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.2),
                                Color.purple.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 100,
                            endRadius: 350
                        )
                    )
                    .scaleEffect(1.1)
                    .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: timerManager.isActive)
            }
        }
        .ignoresSafeArea()
    }

    private var topSliders: some View {
        EQView(
            lowGain: Binding(get: { audioEngine.lowGain }, set: { audioEngine.lowGain = $0; audioEngine.updateEQ() }),
            midGain: Binding(get: { audioEngine.midGain }, set: { audioEngine.midGain = $0; audioEngine.updateEQ() }),
            highGain: Binding(get: { audioEngine.highGain }, set: { audioEngine.highGain = $0; audioEngine.updateEQ() }),
            onChange: {
                audioEngine.updateEQ()
            }
        )
        .padding(.horizontal, 20)
    }

    private var centerContent: some View {
        VStack(spacing: 0) {
            timerRing

            Spacer()
                .frame(height: 32)

            musicBar

            Spacer()
                .frame(height: 32)

            controlButtons

            Spacer()
                .frame(height: 40)
        }
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 8)
                .frame(width: 260, height: 260)

            Circle()
                .trim(from: 0, to: timerManager.progress)
                .stroke(
                    AngularGradient(
                        colors: [.blue, .purple, .blue.opacity(0.5)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 260, height: 260)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 10) {
                Text(timerManager.timeDisplay)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    .monospacedDigit()

                Text(timerManager.isActive ? "focusing" : "tap to set time")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            }
            .onTapGesture {
                if !timerManager.isActive {
                    showingDurationPicker = true
                }
            }
        }
    }

    private var musicBar: some View {
        HStack(spacing: 12) {
            Button {
                showingMusicSelector = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: audioEngine.isPlaying ? "speaker.wave.2.fill" : "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(audioEngine.isPlaying ? .blue : .primary)

                    if let category = audioEngine.currentCategory {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                            
                            if audioEngine.isPlaying {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 6, height: 6)
                                        .opacity(0.8)
                                    Text("正在播放...")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("点击添加氛围音乐")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Image(systemName: "list.bullet")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(.primary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 32) {
            // 番茄钟控制按钮
            Button {
                if timerManager.isActive {
                    timerManager.pause()
                } else {
                    timerManager.start()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: timerManager.isActive ? "pause.fill" : "timer")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("番茄钟")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80, height: 80)
                .background(.regularMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }

            // 音乐播放控制按钮
            Button {
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.play()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: audioEngine.isPlaying ? "music.note" : "music.note")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(audioEngine.currentCategory == nil ? .secondary : Color.primary.opacity(0.85))
                    Text("音乐")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80, height: 80)
                .background(.regularMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .disabled(audioEngine.currentCategory == nil)
        }
    }

    private var durationPickerSheet: some View {
        NavigationView {
            VStack(spacing: 32) {
                Text("专注时长")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 20)

                Picker("分钟", selection: Binding(
                    get: { timerManager.durationMinutes },
                    set: { timerManager.setDuration(minutes: $0) }
                )) {
                    ForEach([5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { minute in
                        Text("\(minute) 分钟").tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)

                Spacer()
            }
            .padding()
            .background(.regularMaterial)
            .navigationTitle("设置时长")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showingDurationPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var musicSelectorSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    categorySection(title: "ASMR", titleColor: .purple, categories: [.fireplace, .ocean, .forest])
                    categorySection(title: "纯音乐", titleColor: .blue, categories: [.electronic, .meditation, .nightPiano])
                    importSection
                }
                .padding()
            }
            .background(.regularMaterial)
            .navigationTitle("音乐库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showingMusicSelector = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func categorySection(title: String, titleColor: Color, categories: [MusicCategory]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(titleColor)

            ForEach(categories, id: \.self) { category in
                let items = musicLibrary.getAllMusicItems(for: category)
                if !items.isEmpty {
                    categoryButton(category: category, items: items, titleColor: titleColor)
                }
            }
        }
    }

    private func categoryButton(category: MusicCategory, items: [MusicItem], titleColor: Color) -> some View {
        Button {
            selectCategory(category, items: items)
        } label: {
            HStack {
                Image(systemName: audioEngine.currentCategory == category ? "speaker.wave.2.fill" : "music.note")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(audioEngine.currentCategory == category ? .blue : titleColor.opacity(0.7))

                Text(category.rawValue)
                    .font(.system(size: 15, weight: audioEngine.currentCategory == category ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Text("(\(items.count)首)")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(.secondary)

                Spacer()

                if audioEngine.currentCategory == category {
                    Text("播放中")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                audioEngine.currentCategory == category
                    ? Color.blue.opacity(0.15)
                    : Color.primary.opacity(0.06)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        audioEngine.currentCategory == category
                            ? Color.blue.opacity(0.4)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
    }

    private func selectCategory(_ category: MusicCategory, items: [MusicItem]) {
        audioEngine.switchCategory(category, items: items)
        showingMusicSelector = false
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的导入")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.orange)

                Spacer()

                Button {
                    isEditingImports.toggle()
                    editMode = isEditingImports ? .active : .inactive
                } label: {
                    Text(isEditingImports ? "完成" : "编辑")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                Menu {
                    Button {
                        pendingPickerType = .file
                        showingMusicSelector = false
                    } label: {
                        Label("从文件", systemImage: "folder")
                    }
                    Button {
                        pendingPickerType = .video
                        showingMusicSelector = false
                    } label: {
                        Label("从视频", systemImage: "video")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("添加")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            if musicLibrary.importedItems.isEmpty {
                Text("暂无导入的歌曲")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(musicLibrary.importedItems) { item in
                        HStack {
                            if isEditingImports {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.red)
                            }

                            Image(systemName: audioEngine.currentCategory == item.category ? "speaker.wave.2.fill" : "music.note")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(audioEngine.currentCategory == item.category ? .blue : .orange.opacity(0.7))

                            Text(item.name)
                                .font(.system(size: 15, weight: audioEngine.currentCategory == item.category ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            if audioEngine.currentCategory == item.category && !isEditingImports {
                                Text("播放中")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            audioEngine.currentCategory == item.category
                                ? Color.blue.opacity(0.15)
                                : Color.primary.opacity(0.06)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isEditingImports {
                                selectMusic(item)
                            }
                        }
                    }
                    .onDelete(perform: deleteImportedItems)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
                .id(musicListRefreshId)
            }
        }
    }

    private func deleteImportedItems(at offsets: IndexSet) {
        for index in offsets {
            let item = musicLibrary.importedItems[index]

            if audioEngine.currentCategory == item.category {
                audioEngine.stop()
            }

            if let track = tracks.first(where: { $0.name == item.name }) {
                modelContext.delete(track)
            }

            musicLibrary.removeImportedItem(at: index)
        }
    }

    private func selectMusic(_ item: MusicItem) {
        let items = musicLibrary.getAllMusicItems(for: item.category)
        audioEngine.switchCategory(item.category, items: items)
        showingMusicSelector = false
    }

    private func loadFirstTrackIfNeeded() {
        // 自动加载功能已移除，用户需要手动选择音乐类别
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }

            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    print("ContentView: Read \(data.count) bytes from \(url.lastPathComponent)")
                    let name = url.deletingPathExtension().lastPathComponent
                    let fileExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
                    let localFileName = "\(UUID().uuidString).\(fileExtension)"

                    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let localURL = documentsURL.appendingPathComponent(localFileName)
                    try data.write(to: localURL)
                    print("ContentView: Wrote \(data.count) bytes to \(localURL.path)")
                    print("ContentView: File exists after write = \(FileManager.default.fileExists(atPath: localURL.path))")

                    let track = Track(name: name, audioData: data)
                    modelContext.insert(track)

                    let importedItem = MusicItem(name: name, category: .pureMusic, localFileName: localFileName)
                    musicLibrary.addImportedItem(importedItem)
                    musicListRefreshId = UUID()

                    lastImportedSongName = name
                    showingImportSuccess = true

                    audioEngine.loadPlaylist(items: [importedItem], category: .pureMusic)
                    audioEngine.play()
                } catch {
                    print("Failed to import audio: \(error)")
                }
            }

        case .failure(let error):
            print("File import failed: \(error)")
        }
    }

    private func handleVideoSelection(_ item: PhotosPickerItem) {
        isProcessingVideo = true

        Task {
            do {
                guard let video = try await item.loadTransferable(type: VideoTransferable.self) else {
                    await MainActor.run { self.isProcessingVideo = false }
                    return
                }

                let audioData = try await videoConverter.convertVideoToAudio(from: video.url)

                await MainActor.run {
                    self.isProcessingVideo = false
                    let name = "Video_\(Int(Date().timeIntervalSince1970))"
                    let localFileName = "\(UUID().uuidString).m4a"

                    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let localURL = documentsURL.appendingPathComponent(localFileName)
                    do {
                        try audioData.write(to: localURL)
                    } catch {
                        print("Failed to save converted audio: \(error)")
                    }

                    let track = Track(name: name, audioData: audioData)
                    self.modelContext.insert(track)
                    let importedItem = MusicItem(name: name, category: .pureMusic, localFileName: localFileName)
                    self.musicLibrary.addImportedItem(importedItem)
                    self.musicListRefreshId = UUID()

                    self.lastImportedSongName = name
                    self.showingImportSuccess = true

                    self.audioEngine.loadPlaylist(items: [importedItem], category: .pureMusic)
                    self.audioEngine.play()
                }
            } catch {
                await MainActor.run {
                    self.isProcessingVideo = false
                    print("Video conversion failed: \(error)")
                }
            }
        }
    }

    private var conversionLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text("正在将视频转换为音频...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)

                if videoConverter.conversionProgress > 0 {
                    ProgressView(value: videoConverter.conversionProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(width: 200)

                    Text("\(Int(videoConverter.conversionProgress * 100))%")
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button("取消") {
                    videoConverter.cancelConversion()
                    isProcessingVideo = false
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 8)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return Self(url: tempURL)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: isDragging ? 10 : 6)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geometry.size.width * CGFloat(value)), height: isDragging ? 10 : 6)

                Circle()
                    .fill(.white)
                    .frame(width: isDragging ? 26 : 22, height: isDragging ? 26 : 22)
                    .shadow(color: .black.opacity(0.3), radius: isDragging ? 6 : 4, y: 2)
                    .offset(x: max(0, min(geometry.size.width - (isDragging ? 26 : 22), geometry.size.width * CGFloat(value) - (isDragging ? 13 : 11))))
                    .scaleEffect(isDragging ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3), value: isDragging)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let newValue = gesture.location.x / geometry.size.width
                        value = min(max(newValue, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 28)
    }
}

struct MarqueeText: View {
    let text: String
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
                .offset(x: offset)
                .onAppear {
                    startAnimation(containerWidth: geometry.size.width)
                }
        }
        .frame(height: 20)
        .clipped()
    }

    private func startAnimation(containerWidth: CGFloat) {
        let textWidth = text.count * 8

        guard CGFloat(textWidth) > containerWidth else { return }

        withAnimation(.linear(duration: Double(textWidth) / 25).repeatForever(autoreverses: false)) {
            offset = -CGFloat(textWidth)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Track.self, inMemory: true)
}