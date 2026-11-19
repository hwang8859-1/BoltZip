import BoltZipCore
import CryptoKit
import Foundation

struct SemanticVersion: Comparable, Hashable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        if let dashIdx = cleaned.firstIndex(of: "-") {
            cleaned = String(cleaned[..<dashIdx])
        }
        let parts = cleaned.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.major = parts[0]
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    var formatted: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct UpdateReleaseInfo: Identifiable, Hashable, Sendable {
    let version: String
    let title: String
    let releaseNotes: String
    let htmlURL: URL
    let dmgURL: URL?
    let dmgFileName: String?
    let dmgSizeBytes: UInt64
    let sha256SumsURL: URL?

    var id: String { version }
}

enum UpdateCheckOutcome: Sendable {
    case upToDate(currentVersion: String)
    case updateAvailable(UpdateReleaseInfo)
}

enum UpdateError: LocalizedError, Sendable {
    case networkFailed(String)
    case noDMGAsset
    case missingChecksumManifest
    case checksumMismatch(expected: String, actual: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .networkFailed(let msg): return msg
        case .noDMGAsset: return "Release does not contain a macOS arm64 DMG installer."
        case .missingChecksumManifest: return "Release does not contain a SHA256SUMS.txt manifest."
        case .checksumMismatch(let expected, let actual):
            return "DMG SHA-256 verification failed (expected \(expected.prefix(12))..., got \(actual.prefix(12))...)."
        case .invalidResponse: return "Invalid update feed response."
        }
    }
}

enum UpdateCheckerService {
    static let githubReleasesAPI = "https://api.github.com/repos/hwang8859-1/BoltZip/releases?per_page=10"
    static let customFeedDefaultsKey = "BoltZip.CustomUpdateFeedURL"
    static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    private struct GitHubAssetDTO: Decodable {
        let name: String
        let size: UInt64?
        let browser_download_url: String
    }

    private struct GitHubReleaseDTO: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let html_url: String
        let assets: [GitHubAssetDTO]
    }

    static func currentAppVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? BoltZipVersion.current
    }

    static func feedURL() -> URL {
        if let custom = UserDefaults.standard.string(forKey: customFeedDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty,
           let url = URL(string: custom),
           url.scheme == "https" {
            return url
        }
        return URL(string: githubReleasesAPI)!
    }

    static func checkForUpdates(
        force: Bool,
        savedETag: String,
        skippedVersion: String,
        lastCheckTimestamp: TimeInterval
    ) async throws -> (outcome: UpdateCheckOutcome, newETag: String?) {
        let now = Date().timeIntervalSince1970
        let currentStr = currentAppVersionString()
        guard let currentSemVer = SemanticVersion(currentStr) else {
            return (.upToDate(currentVersion: currentStr), savedETag.isEmpty ? nil : savedETag)
        }

        if !force, lastCheckTimestamp > 0, (now - lastCheckTimestamp) < autoCheckInterval {
            return (.upToDate(currentVersion: currentStr), savedETag.isEmpty ? nil : savedETag)
        }

        var request = URLRequest(url: feedURL(), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BoltZip/\(currentStr) macOS", forHTTPHeaderField: "User-Agent")
        if !force && !savedETag.isEmpty {
            request.setValue(savedETag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        if http.statusCode == 304 {
            return (.upToDate(currentVersion: currentStr), savedETag)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.networkFailed("HTTP \(http.statusCode)")
        }

        let nextETag = http.value(forHTTPHeaderField: "ETag")
        let releases = try JSONDecoder().decode([GitHubReleaseDTO].self, from: data)

        // Isolate 1.x mainline track away from 0.9.x LTS and future breaking major tracks
        let candidates: [(SemanticVersion, GitHubReleaseDTO)] = releases.compactMap { rel in
            guard !rel.draft && !rel.prerelease,
                  let ver = SemanticVersion(rel.tag_name),
                  ver.major == currentSemVer.major,
                  ver > currentSemVer else {
                return nil
            }
            return (ver, rel)
        }
        .sorted { $0.0 > $1.0 }

        guard let (latestVer, latestRelease) = candidates.first else {
            return (.upToDate(currentVersion: currentStr), nextETag)
        }

        if !force && !skippedVersion.isEmpty && skippedVersion == latestVer.formatted {
            return (.upToDate(currentVersion: currentStr), nextETag)
        }

        let dmgAsset = latestRelease.assets.first {
            let n = $0.name.lowercased()
            return n.hasSuffix(".dmg") && (n.contains("arm64") || !n.contains("x86_64"))
        } ?? latestRelease.assets.first { $0.name.lowercased().hasSuffix(".dmg") }

        let shaAsset = latestRelease.assets.first {
            $0.name.uppercased().contains("SHA256SUMS")
        }

        guard let htmlURL = URL(string: latestRelease.html_url) else {
            throw UpdateError.invalidResponse
        }

        let info = UpdateReleaseInfo(
            version: latestVer.formatted,
            title: latestRelease.name ?? "BoltZip v\(latestVer.formatted)",
            releaseNotes: latestRelease.body ?? "",
            htmlURL: htmlURL,
            dmgURL: dmgAsset.flatMap { URL(string: $0.browser_download_url) },
            dmgFileName: dmgAsset?.name,
            dmgSizeBytes: dmgAsset?.size ?? 0,
            sha256SumsURL: shaAsset.flatMap { URL(string: $0.browser_download_url) }
        )
        return (.updateAvailable(info), nextETag)
    }

    static func downloadAndVerifyDMG(release: UpdateReleaseInfo) async throws -> URL {
        guard let dmgRemoteURL = release.dmgURL,
              let dmgName = release.dmgFileName else {
            throw UpdateError.noDMGAsset
        }
        guard let sumsURL = release.sha256SumsURL else {
            throw UpdateError.missingChecksumManifest
        }

        let (sumsData, sumsResp) = try await URLSession.shared.data(from: sumsURL)
        guard let sumsHTTP = sumsResp as? HTTPURLResponse, (200..<300).contains(sumsHTTP.statusCode),
              let sumsText = String(data: sumsData, encoding: .utf8) else {
            throw UpdateError.missingChecksumManifest
        }

        guard let expectedHash = parseSHA256(from: sumsText, filename: dmgName) else {
            throw UpdateError.missingChecksumManifest
        }

        let (tempDMGURL, dmgResp) = try await URLSession.shared.download(from: dmgRemoteURL)
        guard let dmgHTTP = dmgResp as? HTTPURLResponse, (200..<300).contains(dmgHTTP.statusCode) else {
            try? FileManager.default.removeItem(at: tempDMGURL)
            throw UpdateError.networkFailed("Failed downloading installer image.")
        }

        let actualHash = try computeFileSHA256Hex(at: tempDMGURL)
        guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
            try? FileManager.default.removeItem(at: tempDMGURL)
            throw UpdateError.checksumMismatch(expected: expectedHash, actual: actualHash)
        }

        let fm = FileManager.default
        let downloadsDir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        var destURL = downloadsDir.appendingPathComponent(dmgName)
        if fm.fileExists(atPath: destURL.path) {
            try? fm.removeItem(at: destURL)
        }
        do {
            try fm.moveItem(at: tempDMGURL, to: destURL)
        } catch {
            destURL = fm.temporaryDirectory.appendingPathComponent(dmgName)
            try? fm.removeItem(at: destURL)
            try fm.moveItem(at: tempDMGURL, to: destURL)
        }
        return destURL
    }

    static func parseSHA256(from manifest: String, filename: String) -> String? {
        for rawLine in manifest.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            let file = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            if file == filename || URL(fileURLWithPath: file).lastPathComponent == filename {
                if hash.count == 64 {
                    return hash
                }
            }
        }
        return nil
    }

    static func computeFileSHA256Hex(at url: URL) throws -> String {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            let chunk = try fh.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
