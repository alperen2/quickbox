import Foundation
import Combine

@MainActor
final class IndexManager: ObservableObject {
    static let shared = IndexManager()

    @Published private(set) var availableTags: [String] = []
    @Published private(set) var availableProjects: [String] = []
    
    // We export a stream of arrays so UI can listen to it asynchronously
    var tagsPublisher: AnyPublisher<[String], Never> {
        $availableTags.eraseToAnyPublisher()
    }
    
    var projectsPublisher: AnyPublisher<[String], Never> {
        $availableProjects.eraseToAnyPublisher()
    }
    
    private init() {}

    /// Resolves the storage folder and scans it in the background.
    /// Security-scoped access is held for the whole scan and released only after it finishes,
    /// otherwise the sandbox denies reads once the caller's scope ends.
    func buildIndex(using storageResolver: StorageResolving) {
        guard let folderURL = try? storageResolver.resolvedBaseURL() else { return }

        Task {
            defer { storageResolver.stopAccess(for: folderURL) }
            let (newTags, newProjects) = await Self.scanFiles(in: folderURL)
            self.availableTags = newTags
            self.availableProjects = newProjects
        }
    }
    
    private static func scanFiles(in folderURL: URL) async -> ([String], [String]) {
        return await Task.detached {
            let fileManager = FileManager.default
            do {
                let contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                let markdownFiles = contents.filter { $0.pathExtension == "md" }

                var uniqueTags = Set<String>()
                var uniqueProjects = Set<String>()

                let tagPattern = /#([a-zA-Z0-9_\-]+)/

                for fileURL in markdownFiles {
                    uniqueTags.formUnion(tags(in: fileURL, matching: tagPattern))
                }

                // Each subdirectory is a project holding dated `<date>.md` files
                let projectDirectories = try StorageLayout.projectDirectories(in: folderURL, fileManager: fileManager)
                for directoryURL in projectDirectories {
                    uniqueProjects.insert(directoryURL.lastPathComponent)

                    let projectFiles = (try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
                    for fileURL in projectFiles where fileURL.pathExtension == "md" {
                        uniqueTags.formUnion(tags(in: fileURL, matching: tagPattern))
                    }
                }

                return (Array(uniqueTags).sorted(), Array(uniqueProjects).sorted())
            } catch {
                print("IndexManager failed to build index: \(error)")
                return ([], [])
            }
        }.value
    }

    private nonisolated static func tags(in fileURL: URL, matching pattern: Regex<(Substring, Substring)>) -> [String] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return content.matches(of: pattern).map { String($0.1) }
    }
    
    // Quick injection when a new task is captured so we don't need a full rebuild
    func inject(tags: [String], project: String?) {
        var didChangeTags = false
        var didChangeProjects = false
        
        for tag in tags {
            if !availableTags.contains(tag) {
                availableTags.append(tag)
                didChangeTags = true
            }
        }
        
        if let proj = project, !availableProjects.contains(proj) {
            availableProjects.append(proj)
            didChangeProjects = true
        }
        
        if didChangeTags { availableTags.sort() }
        if didChangeProjects { availableProjects.sort() }
    }
}
