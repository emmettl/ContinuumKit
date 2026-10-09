import DocumentKit
import Foundation
import Testing

@Suite("Project container JSON diagnostics")
struct ProjectArchiveDiagnosticsTests {
    private func archive() throws -> ProjectArchive {
        try ProjectArchive(
            manifest: ProjectManifest(documentType: "tests", producer: "Tests"),
            files: [
                "scene.json": Data("{}".utf8), "settings.json": Data("{}".utf8),
                "view.json": Data("{}".utf8),
            ])
    }

    private func expectError(_ message: String, operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Invalid project JSON was accepted")
        } catch {
            #expect(error is ProjectFileError)
            #expect(error.localizedDescription == message)
        }
    }

    @Test(
        "Malformed JSON names its payload in archive, wrapper and disk readers",
        arguments: ["scene.json", "settings.json", "view.json"])
    func malformed(file: String) throws {
        for data in [Data("{".utf8), Data([0xff])] {
            var project = try archive()
            project.files[file] = data
            let message = "\(file) is not valid JSON."
            expectError(message) { try project.validate() }
            expectError(message) {
                _ = try ProjectArchive(manifest: project.manifest, files: project.files)
            }

            var wrappers = project.files.mapValues { FileWrapper(regularFileWithContents: $0) }
            wrappers["manifest.json"] = FileWrapper(
                regularFileWithContents: try ProjectArchive.encodeJSON(project.manifest))
            let wrapper = FileWrapper(directoryWithFileWrappers: wrappers)
            expectError(message) { _ = try ProjectArchive(fileWrapper: wrapper) }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
            expectError(message) { _ = try ProjectArchive.read(from: url) }
            #expect(try Data(contentsOf: url.appendingPathComponent(file)) == data)
        }
    }

    @Test(
        "Valid non-object JSON has a shape error rather than a syntax error",
        arguments: ["scene.json", "settings.json", "view.json"])
    func objectRequired(file: String) throws {
        for json in ["[]", "null", "42", "true", "\"text\""] {
            var project = try archive()
            project.files[file] = Data(json.utf8)
            expectError("\(file) must contain a JSON object.") { try project.validate() }
        }
    }
}
