import Foundation
import Combine

enum MusicCategory: String, CaseIterable, Identifiable, Codable {
    case asmr = "ASMR"
    case pureMusic = "Pure Music"
    case electronic = "电子"
    case meditation = "冥想"
    case nightPiano = "夜钢琴"
    case fireplace = "壁炉"
    case ocean = "海洋"
    case forest = "森林"

    var id: String { rawValue }
}

struct MusicItem: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let category: MusicCategory
    let isBuiltIn: Bool
    let bundleName: String?
    var localFileName: String?

    init(name: String, category: MusicCategory, bundleName: String? = nil, localFileName: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.category = category
        self.isBuiltIn = bundleName != nil
        self.bundleName = bundleName
        self.localFileName = localFileName
    }

    static func == (lhs: MusicItem, rhs: MusicItem) -> Bool {
        lhs.name == rhs.name && lhs.localFileName == rhs.localFileName
    }
}

final class MusicLibrary: ObservableObject {
    @Published var builtInItems: [MusicCategory: [MusicItem]] = [:]
    @Published var importedItems: [MusicItem] = []

    private let storageKey = "MuteMusicLibrary.importedItems"

    var allBuiltInItems: [MusicItem] {
        builtInItems.values.flatMap { $0 }
    }

    var allItems: [MusicItem] {
        allBuiltInItems + importedItems
    }

    init() {
        loadBuiltInLibrary()
        loadImportedItems()
    }

    private func loadBuiltInLibrary() {
        builtInItems[.asmr] = [
            MusicItem(name: "深海潮汐", category: .asmr, bundleName: "asmr_ocean"),
            MusicItem(name: "雨后森林", category: .asmr, bundleName: "asmr_forest"),
            MusicItem(name: "壁炉轻响", category: .asmr, bundleName: "asmr_fireplace")
        ]

        builtInItems[.pureMusic] = [
            MusicItem(name: "晨间冥想", category: .pureMusic, bundleName: "pure_meditation"),
            MusicItem(name: "夜色钢琴", category: .pureMusic, bundleName: "pure_piano"),
            MusicItem(name: "极简电子", category: .pureMusic, bundleName: "pure_ambient")
        ]

        builtInItems[.electronic] = [
            MusicItem(name: "电子1", category: .electronic, bundleName: "电子1"),
            MusicItem(name: "电子2", category: .electronic, bundleName: "电子2"),
            MusicItem(name: "电子3", category: .electronic, bundleName: "电子3"),
            MusicItem(name: "电子4", category: .electronic, bundleName: "电子4")
        ]

        builtInItems[.meditation] = [
            MusicItem(name: "冥想1", category: .meditation, bundleName: "冥想1"),
            MusicItem(name: "冥想2", category: .meditation, bundleName: "冥想2"),
            MusicItem(name: "冥想3", category: .meditation, bundleName: "冥想3")
        ]

        builtInItems[.nightPiano] = [
            MusicItem(name: "夜钢琴1", category: .nightPiano, bundleName: "夜钢琴1"),
            MusicItem(name: "夜钢琴2", category: .nightPiano, bundleName: "夜钢琴2"),
            MusicItem(name: "夜钢琴3", category: .nightPiano, bundleName: "夜钢琴3")
        ]

        builtInItems[.fireplace] = [
            MusicItem(name: "壁炉暖梦", category: .fireplace, bundleName: "壁炉暖梦(1)")
        ]

        builtInItems[.ocean] = [
            MusicItem(name: "浪花之谧", category: .ocean, bundleName: "浪花之谧(1)"),
            MusicItem(name: "深海潮汐", category: .ocean, bundleName: "深海潮汐(1)")
        ]

        builtInItems[.forest] = [
            MusicItem(name: "雨后森林", category: .forest, bundleName: "雨后森林(1)")
        ]
    }

    private func loadImportedItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([MusicItem].self, from: data) else {
            return
        }
        importedItems = items
    }

    private func saveImportedItems() {
        guard let data = try? JSONEncoder().encode(importedItems) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func addImportedItem(_ item: MusicItem) {
        importedItems.append(item)
        saveImportedItems()
    }

    func removeImportedItem(at index: Int) {
        guard index >= 0 && index < importedItems.count else { return }
        let item = importedItems[index]

        if let localFileName = item.localFileName {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsURL.appendingPathComponent(localFileName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        importedItems.remove(at: index)
        saveImportedItems()
    }

    func findItem(byName name: String) -> MusicItem? {
        allItems.first { $0.name == name }
    }

    func builtInItems(for category: MusicCategory) -> [MusicItem] {
        builtInItems[category] ?? []
    }

    func getLocalFileURL(for item: MusicItem) -> URL? {
        guard let localFileName = item.localFileName else { return nil }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(localFileName)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func getAllMusicItems(for category: MusicCategory) -> [MusicItem] {
        var items: [MusicItem] = []

        items.append(contentsOf: builtInItems[category] ?? [])

        let importedInCategory = importedItems.filter { $0.category == category }
        items.append(contentsOf: importedInCategory)

        return items
    }

    func getAllBuiltInCategories() -> [MusicCategory] {
        return MusicCategory.allCases.filter { category in
            !(builtInItems[category] ?? []).isEmpty
        }
    }
}