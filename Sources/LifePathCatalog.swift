import Foundation

enum LifePathCatalogError: Error, LocalizedError {
    case missingResource(String)
    case decodeFailed(String)
    case validationFailed([String])

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Missing Life Path resource: \(name)"
        case .decodeFailed(let detail):
            return "Life Path decode failed: \(detail)"
        case .validationFailed(let issues):
            return "Life Path validation failed: \(issues.joined(separator: "; "))"
        }
    }
}

enum LifePathValidation {
    static func validate(_ file: LifePathListFile) -> [String] {
        var issues: [String] = []
        if file.stages.isEmpty {
            issues.append("no stages")
        }
        if file.entries.isEmpty {
            issues.append("no entries")
        }
        var seenIds = Set<String>()
        var seenFronts = Set<String>()
        let stageIds = Set(file.stages.map(\.id))
        for entry in file.entries {
            if !seenIds.insert(entry.id).inserted {
                issues.append("duplicate id \(entry.id)")
            }
            let key = entry.front.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seenFronts.insert(key).inserted {
                issues.append("duplicate front \(entry.front)")
            }
            if !stageIds.contains(entry.stageId) {
                issues.append("entry \(entry.id) unknown stage \(entry.stageId)")
            }
            if entry.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("empty front \(entry.id)")
            }
        }
        return issues
    }
}

/// Loads versioned Life Path JSON from the app / module bundle.
enum LifePathCatalog {
    private static let decoder = JSONDecoder()

    static func resourceURL(name: String, ext: String) -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "LifePath") {
            return url
        }
        #endif
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "LifePath") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        let candidates = [
            "Sources/LifePath/\(name).\(ext)",
            "LifePath/\(name).\(ext)",
            "Resources/LifePath/\(name).\(ext)",
        ]
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        for rel in candidates {
            let path = (cwd as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Walk up from cwd for package tests
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<5 {
            let path = dir.appendingPathComponent("Sources/LifePath/\(name).\(ext)").path
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    static func loadManifest() throws -> LifePathManifest {
        guard let url = resourceURL(name: "life_path_manifest", ext: "json") else {
            throw LifePathCatalogError.missingResource("life_path_manifest.json")
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(LifePathManifest.self, from: data)
        } catch let error as LifePathCatalogError {
            throw error
        } catch {
            throw LifePathCatalogError.decodeFailed(error.localizedDescription)
        }
    }

    static func loadList(language: LifePathLanguage) throws -> LifePathListFile {
        try loadList(resourceBaseName: language.resourceBaseName)
    }

    static func loadList(resourceBaseName: String) throws -> LifePathListFile {
        guard let url = resourceURL(name: resourceBaseName, ext: "json") else {
            throw LifePathCatalogError.missingResource("\(resourceBaseName).json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LifePathCatalogError.missingResource("\(resourceBaseName).json")
        }
        return try decodeAndValidate(data: data)
    }

    static func decodeAndValidate(data: Data) throws -> LifePathListFile {
        let file: LifePathListFile
        do {
            file = try decoder.decode(LifePathListFile.self, from: data)
        } catch {
            throw LifePathCatalogError.decodeFailed(error.localizedDescription)
        }
        let issues = LifePathValidation.validate(file)
        if !issues.isEmpty {
            throw LifePathCatalogError.validationFailed(issues)
        }
        return file
    }
}
