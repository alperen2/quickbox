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

    func buildIndex(in folderURL: URL) {
        Task {
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
                
                // Add known project names based on filenames directly
                for fileURL in markdownFiles {
                    let filename = fileURL.deletingPathExtension().lastPathComponent
                    // If it's not a date-based log, consider it a known project
                    let isDateLog = filename.firstMatch(of: /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) != nil
                    if !isDateLog {
                        uniqueProjects.insert(filename)
                    }

                    // Scan file content for tags
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        for match in content.matches(of: tagPattern) {
                            uniqueTags.insert(String(match.1))
                        }
                    }
                }

                return (Array(uniqueTags).sorted(), Array(uniqueProjects).sorted())
            } catch {
                print("IndexManager failed to build index: \(error)")
                return ([], [])
            }
        }.value
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
