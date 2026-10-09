import DocumentKit
import Foundation
import Testing

@Suite("Project manifest diagnostics")
struct ProjectManifestDiagnosticsTests {
    private func payload() throws -> [String: Any] {
        let data = try ProjectArchive.encodeJSON(ProjectManifest(documentType: "tests", producer: "Tests"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func expectError(_ data: Data, message: String) throws {
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: data),
            "scene.json": FileWrapper(regularFileWithContents: Data("{}".utf8)),
            "settings.json": FileWrapper(regularFileWithContents: Data("{}".utf8)),
        ])
        func check(_ operation: () throws -> Void) {
            do {
                try operation()
                Issue.record("Invalid manifest was accepted")
            } catch {
                #expect(error is ProjectFileError)
                #expect(error.localizedDescription == message)
            }
        }
        check { _ = try ProjectArchive(fileWrapper: wrapper) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        check { _ = try ProjectArchive.read(from: url) }
        #expect(try Data(contentsOf: url.appendingPathComponent("manifest.json")) == data)
    }

    @Test(
        "Missing required metadata identifies its field",
        arguments: ["format", "schemaVersion", "documentID", "documentType", "producer", "assets"])
    func missingFields(field: String) throws {
        var manifest = try payload()
        manifest.removeValue(forKey: field)
        try expectError(
            JSONSerialization.data(withJSONObject: manifest),
            message: "manifest.json is missing the required field \"\(field)\".")
    }

    @Test("Wrong types and null metadata have field-specific errors")
    func invalidValues() throws {
        var manifest = try payload()
        manifest["schemaVersion"] = "1"
        try expectError(
            JSONSerialization.data(withJSONObject: manifest),
            message: "manifest.json has the wrong value type at \"schemaVersion\".")
        manifest = try payload()
        manifest["producer"] = NSNull()
        try expectError(
            JSONSerialization.data(withJSONObject: manifest),
            message: "manifest.json requires a non-null value at \"producer\".")
        manifest = try payload()
        manifest["assets"] = [["id": "invalid", "path": "assets/source.obj", "sha256": "unused"]]
        try expectError(
            JSONSerialization.data(withJSONObject: manifest),
            message: "manifest.json contains an invalid value at \"assets[0].id\".")
    }

    @Test("Malformed JSON and invalid UTF-8 identify the manifest")
    func malformed() throws {
        for data in [Data("{".utf8), Data([0xff])] {
            try expectError(data, message: "manifest.json is not valid JSON.")
        }
    }

    @Test("Valid non-object JSON identifies the manifest root")
    func rootValues() throws {
        try expectError(
            Data("[]".utf8), message: "manifest.json has the wrong value type at \"root\".")
        try expectError(
            Data("null".utf8), message: "manifest.json requires a non-null value at \"root\".")
    }

    @Test("Semantic checks and unsupported-version precedence remain actionable")
    func semanticValidation() throws {
        var manifest = try payload()
        manifest["producer"] = ""
        try expectError(
            JSONSerialization.data(withJSONObject: manifest),
            message: "The project manifest is incomplete.")
        manifest = ["format": "unknown", "schemaVersion": 99]
        try expectError(
            JSONSerialization.data(withJSONObject: manifest), message: "Unknown project format.")
        manifest = ["format": ProjectManifest.formatIdentifier, "schemaVersion": 99]
        try expectError(
            JSONSerialization.data(withJSONObject: manifest),
            message: "This project uses format version 99. This app supports version 1.")
    }
}
