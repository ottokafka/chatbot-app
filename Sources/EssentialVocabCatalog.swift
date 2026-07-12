import Foundation

/// Loads versioned essential-vocab JSON from the app / module bundle.
enum EssentialVocabCatalog {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// Resolve a resource URL: Bundle.module (SPM library) → main EssentialVocab/ → main root.
    static func resourceURL(name: String, ext: String) -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "EssentialVocab") {
            return url
        }
        #endif
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "EssentialVocab") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        // Dev fallback: package-relative path next to executable / cwd
        let candidates = [
            "Sources/EssentialVocab/\(name).\(ext)",
            "EssentialVocab/\(name).\(ext)",
            "Resources/EssentialVocab/\(name).\(ext)",
        ]
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        for rel in candidates {
            let path = (cwd as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static func loadManifest() throws -> EssentialVocabManifest {
        guard let url = resourceURL(name: "manifest", ext: "json") else {
            throw EssentialVocabCatalogError.missingResource("manifest.json")
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(EssentialVocabManifest.self, from: data)
        } catch let error as EssentialVocabCatalogError {
            throw error
        } catch {
            throw EssentialVocabCatalogError.decodeFailed(error.localizedDescription)
        }
    }

    static func loadList(language: EssentialListLanguage) throws -> EssentialVocabListFile {
        try loadList(resourceBaseName: language.resourceBaseName)
    }

    static func loadList(resourceBaseName: String) throws -> EssentialVocabListFile {
        guard let url = resourceURL(name: resourceBaseName, ext: "json") else {
            throw EssentialVocabCatalogError.missingResource("\(resourceBaseName).json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EssentialVocabCatalogError.missingResource("\(resourceBaseName).json")
        }
        let file: EssentialVocabListFile
        do {
            file = try decoder.decode(EssentialVocabListFile.self, from: data)
        } catch {
            throw EssentialVocabCatalogError.decodeFailed(error.localizedDescription)
        }
        let issues = EssentialVocabValidation.validate(file)
        if !issues.isEmpty {
            throw EssentialVocabCatalogError.validationFailed(issues)
        }
        return file
    }

    /// Decode + validate from raw data (tests / tools).
    static func decodeAndValidate(data: Data) throws -> EssentialVocabListFile {
        let file: EssentialVocabListFile
        do {
            file = try decoder.decode(EssentialVocabListFile.self, from: data)
        } catch {
            throw EssentialVocabCatalogError.decodeFailed(error.localizedDescription)
        }
        let issues = EssentialVocabValidation.validate(file)
        if !issues.isEmpty {
            throw EssentialVocabCatalogError.validationFailed(issues)
        }
        return file
    }
}
