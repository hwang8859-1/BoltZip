@testable import BoltZipCore
import XCTest

final class MCPServerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoltZipMCPTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testInitializeAndPing() async throws {
        let initRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
        """
        let initResponse = await MCPServer.handleMessage(rawJSON: initRequest)
        XCTAssertNotNil(initResponse)
        let initData = try XCTUnwrap(initResponse?.data(using: .utf8))
        let initJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: initData) as? [String: Any])
        XCTAssertEqual(initJSON["id"] as? Int, 1)
        let result = try XCTUnwrap(initJSON["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "boltzip-mcp")

        let pingRequest = """
        {"jsonrpc":"2.0","id":2,"method":"ping","params":{}}
        """
        let pingResponse = await MCPServer.handleMessage(rawJSON: pingRequest)
        XCTAssertNotNil(pingResponse)
        let pingData = try XCTUnwrap(pingResponse?.data(using: .utf8))
        let pingJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: pingData) as? [String: Any])
        XCTAssertEqual(pingJSON["id"] as? Int, 2)
        XCTAssertNotNil(pingJSON["result"])
    }

    func testToolsListReturnsAllExpectedTools() async throws {
        let listRequest = """
        {"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}
        """
        let response = await MCPServer.handleMessage(rawJSON: listRequest)
        XCTAssertNotNil(response)
        let data = try XCTUnwrap(response?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])

        let toolNames = Set(tools.compactMap { $0["name"] as? String })
        let expectedTools: Set<String> = [
            "boltzip_compress",
            "boltzip_extract",
            "boltzip_list",
            "boltzip_test",
            "boltzip_batch_compress",
            "boltzip_batch_extract",
            "boltzip_recover_zip"
        ]
        XCTAssertTrue(expectedTools.isSubset(of: toolNames))
    }

    func testCompressListTestAndExtractViaMCP() async throws {
        let fileA = tempDirectory.appendingPathComponent("hello.txt")
        let fileB = tempDirectory.appendingPathComponent("notes.md")
        try "Hello World MCP".write(to: fileA, atomically: true, encoding: .utf8)
        try "# Markdown notes".write(to: fileB, atomically: true, encoding: .utf8)

        let targetArchive = tempDirectory.appendingPathComponent("bundle.zip")

        // 1. boltzip_compress
        let compressPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 10,
            "method": "tools/call",
            "params": [
                "name": "boltzip_compress",
                "arguments": [
                    "inputs": [fileA.path, fileB.path],
                    "output": targetArchive.path,
                    "format": "zip"
                ]
            ]
        ]
        let compressReqData = try JSONSerialization.data(withJSONObject: compressPayload)
        let compressReqStr = String(data: compressReqData, encoding: .utf8)!
        let compressResStr = await MCPServer.handleMessage(rawJSON: compressReqStr)
        XCTAssertNotNil(compressResStr)
        let compressRes = try parseToolCallResult(compressResStr!)
        XCTAssertEqual(compressRes.isError, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetArchive.path))

        // 2. boltzip_list
        let listPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 11,
            "method": "tools/call",
            "params": [
                "name": "boltzip_list",
                "arguments": [
                    "archive": targetArchive.path
                ]
            ]
        ]
        let listReqData = try JSONSerialization.data(withJSONObject: listPayload)
        let listResStr = await MCPServer.handleMessage(rawJSON: String(data: listReqData, encoding: .utf8)!)
        let listRes = try parseToolCallResult(listResStr!)
        XCTAssertEqual(listRes.isError, false)
        let listOutput = try parseJSONText(listRes.text)
        let totalEntries = listOutput["totalEntries"] as? Int
        XCTAssertEqual(totalEntries, 2)

        // 3. boltzip_test
        let testPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 12,
            "method": "tools/call",
            "params": [
                "name": "boltzip_test",
                "arguments": [
                    "archive": targetArchive.path
                ]
            ]
        ]
        let testReqData = try JSONSerialization.data(withJSONObject: testPayload)
        let testResStr = await MCPServer.handleMessage(rawJSON: String(data: testReqData, encoding: .utf8)!)
        let testRes = try parseToolCallResult(testResStr!)
        XCTAssertEqual(testRes.isError, false)
        let testOutput = try parseJSONText(testRes.text)
        XCTAssertEqual(testOutput["isHealthy"] as? Bool, true)

        // 4. boltzip_extract
        let destDir = tempDirectory.appendingPathComponent("extracted")
        let extractPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 13,
            "method": "tools/call",
            "params": [
                "name": "boltzip_extract",
                "arguments": [
                    "archive": targetArchive.path,
                    "destination": destDir.path,
                    "mode": "here"
                ]
            ]
        ]
        let extractReqData = try JSONSerialization.data(withJSONObject: extractPayload)
        let extractResStr = await MCPServer.handleMessage(rawJSON: String(data: extractReqData, encoding: .utf8)!)
        let extractRes = try parseToolCallResult(extractResStr!)
        XCTAssertEqual(extractRes.isError, false)

        let extractedA = destDir.appendingPathComponent("hello.txt")
        let readA = try String(contentsOf: extractedA, encoding: .utf8)
        XCTAssertEqual(readA, "Hello World MCP")
    }

    func testBatchCompressAndBatchExtractViaMCP() async throws {
        let folder1 = tempDirectory.appendingPathComponent("folder1")
        let folder2 = tempDirectory.appendingPathComponent("folder2")
        try FileManager.default.createDirectory(at: folder1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)
        try "Content 1".write(to: folder1.appendingPathComponent("f1.txt"), atomically: true, encoding: .utf8)
        try "Content 2".write(to: folder2.appendingPathComponent("f2.txt"), atomically: true, encoding: .utf8)

        let batchOutDir = tempDirectory.appendingPathComponent("batch_archives")

        // Batch compress
        let batchCompPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 20,
            "method": "tools/call",
            "params": [
                "name": "boltzip_batch_compress",
                "arguments": [
                    "items": [folder1.path, folder2.path],
                    "output_directory": batchOutDir.path,
                    "format": "zip"
                ]
            ]
        ]
        let batchCompData = try JSONSerialization.data(withJSONObject: batchCompPayload)
        let batchCompResStr = await MCPServer.handleMessage(rawJSON: String(data: batchCompData, encoding: .utf8)!)
        let batchCompRes = try parseToolCallResult(batchCompResStr!)
        XCTAssertEqual(batchCompRes.isError, false)
        let batchCompOutput = try parseJSONText(batchCompRes.text)
        XCTAssertEqual(batchCompOutput["succeededCount"] as? Int, 2)

        // Batch extract
        let batchExtractDir = tempDirectory.appendingPathComponent("batch_extracted")
        let arc1 = batchOutDir.appendingPathComponent("folder1.zip")
        let arc2 = batchOutDir.appendingPathComponent("folder2.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: arc1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: arc2.path))

        let batchExtPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 21,
            "method": "tools/call",
            "params": [
                "name": "boltzip_batch_extract",
                "arguments": [
                    "archives": [arc1.path, arc2.path],
                    "destination_directory": batchExtractDir.path,
                    "mode": "subfolder"
                ]
            ]
        ]
        let batchExtData = try JSONSerialization.data(withJSONObject: batchExtPayload)
        let batchExtResStr = await MCPServer.handleMessage(rawJSON: String(data: batchExtData, encoding: .utf8)!)
        let batchExtRes = try parseToolCallResult(batchExtResStr!)
        XCTAssertEqual(batchExtRes.isError, false)
        let batchExtOutput = try parseJSONText(batchExtRes.text)
        XCTAssertEqual(batchExtOutput["succeededCount"] as? Int, 2)
    }

    func testErrorHandlingViaMCP() async throws {
        // Unknown method
        let unknownReq = """
        {"jsonrpc":"2.0","id":99,"method":"unknown_method","params":{}}
        """
        let unknownResStr = await MCPServer.handleMessage(rawJSON: unknownReq)
        let unknownData = try XCTUnwrap(unknownResStr?.data(using: .utf8))
        let unknownJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: unknownData) as? [String: Any])
        XCTAssertNotNil(unknownJSON["error"])

        // Non-existent file in extract
        let extractNotFoundPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 100,
            "method": "tools/call",
            "params": [
                "name": "boltzip_extract",
                "arguments": [
                    "archive": "/non/existent/path/archive.zip"
                ]
            ]
        ]
        let notFoundData = try JSONSerialization.data(withJSONObject: extractNotFoundPayload)
        let notFoundResStr = await MCPServer.handleMessage(rawJSON: String(data: notFoundData, encoding: .utf8)!)
        let notFoundRes = try parseToolCallResult(notFoundResStr!)
        XCTAssertEqual(notFoundRes.isError, true)
        XCTAssertTrue(notFoundRes.text.contains("Error:"))
    }

    // MARK: - Helpers

    private func parseToolCallResult(_ raw: String) throws -> (isError: Bool, text: String) {
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let isError = (result["isError"] as? Bool) ?? false
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let first = try XCTUnwrap(content.first)
        let text = (first["text"] as? String) ?? ""
        return (isError, text)
    }

    private func parseJSONText(_ text: String) throws -> [String: Any] {
        let data = try XCTUnwrap(text.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
