import Foundation

// MARK: - Tier folders (disk names + common typo)

enum ModelTierFolder: String, CaseIterable, Identifiable, Hashable {
    case free = "Free"
    case pro = "Pro"
    case ultra = "Ultra"

    var id: String { rawValue }

    /// Names that might appear inside `Models/` in the app bundle (includes `utlra` typo).
    var diskNameAliases: [String] {
        switch self {
        case .free: return ["Free", "free"]
        case .pro: return ["Pro", "pro"]
        case .ultra: return ["Ultra", "ultra", "UTLRA", "utlra", "Utlra"]
        }
    }

    /// Subdirectories used with `Bundle.url(forResource:withExtension:subdirectory:)`.
    var modelsSearchSubpaths: [String] {
        diskNameAliases.map { "Models/\($0)" }
    }
}

// MARK: - One selectable Core ML entry per tier

struct HomeworkTierModel: Identifiable, Equatable, Hashable {
    let id: String
    let tier: ModelTierFolder
    /// Shown in the custom picker
    let title: String
    /// Bundle file name without extension (e.g. llama_3d)
    let resourceStem: String
    let isPlaceholder: Bool
    /// When set, `MLModel` loads from this file URL (from bundle discovery).
    let bundleFileURL: URL?

    static func == (lhs: HomeworkTierModel, rhs: HomeworkTierModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Scans `App.app/Models/<tier>/` for `.mlpackage` / `.mlmodelc` and maps folder typos (e.g. utlra → Ultra).
    static func discover(in bundle: Bundle = .main) -> [HomeworkTierModel] {
        guard let modelsRoot = bundle.resourceURL?.appendingPathComponent("Models", isDirectory: true) else {
            return []
        }
        guard FileManager.default.fileExists(atPath: modelsRoot.path) else { return [] }

        var results: [HomeworkTierModel] = []
        let subs: [URL]
        do {
            subs = try FileManager.default.contentsOfDirectory(
                at: modelsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        for folderURL in subs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let folderName = folderURL.lastPathComponent
            guard let tier = Self.tierForDiskFolderName(folderName) else { continue }

            let files: [URL]
            do {
                files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch { continue }

            for fileURL in files {
                let ext = fileURL.pathExtension.lowercased()
                guard ext == "mlpackage" || ext == "mlmodelc" else { continue }
                let stem = fileURL.deletingPathExtension().lastPathComponent
                let pretty = stem.replacingOccurrences(of: "_", with: " ")
                let mid = "\(tier.rawValue.lowercased())-\(stem)"
                results.append(
                    HomeworkTierModel(
                        id: mid,
                        tier: tier,
                        title: pretty,
                        resourceStem: stem,
                        isPlaceholder: false,
                        bundleFileURL: fileURL
                    )
                )
            }
        }
        return results.sorted { $0.tier.rawValue < $1.tier.rawValue || ($0.tier == $1.tier && $0.title < $1.title) }
    }

    /// Maps a directory name under `Models/` to a tier (handles `utlra` typo).
    static func tierForDiskFolderName(_ name: String) -> ModelTierFolder? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch n {
        case "free": return .free
        case "pro": return .pro
        case "ultra", "utlra": return .ultra
        default: return nil
        }
    }

    static func placeholder(for tier: ModelTierFolder) -> HomeworkTierModel {
        HomeworkTierModel(
            id: "\(tier.rawValue.lowercased())-placeholder",
            tier: tier,
            title: "No model bundled yet",
            resourceStem: "",
            isPlaceholder: true,
            bundleFileURL: nil
        )
    }

    /// Discovered models for a tier, or a single placeholder row if none.
    static func options(for tier: ModelTierFolder, discovered: [HomeworkTierModel]) -> [HomeworkTierModel] {
        let found = discovered.filter { $0.tier == tier }
        if found.isEmpty {
            return [placeholder(for: tier)]
        }
        return found
    }
}
