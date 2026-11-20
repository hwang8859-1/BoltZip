import Foundation
import XCTest
@testable import BoltZipCore

final class RARCompatibilityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BoltZipRAR-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testEncryptedRAR4AndRAR5HeadersRequirePassword() throws {
        for fixture in [RARFixture.encryptedNamesRAR4, .encryptedNamesRAR5] {
            let archive = try writeArchive(fixture)
            XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: archive)) { error in
                guard case BoltZipError.passwordRequired = error else { return XCTFail("\(fixture): \(error)") }
            }
            XCTAssertThrowsError(try BoltArchiveEngine.inspect(archiveURL: archive, password: "incorrect")) { error in
                guard case BoltZipError.wrongPassword = error else { return XCTFail("\(fixture): \(error)") }
            }

            let listing = try BoltArchiveEngine.inspect(archiveURL: archive, password: "password")
            XCTAssertEqual(listing.format, .rar)
            XCTAssertEqual(listing.entries.map(\.path), ["a.txt", "b.txt", "c.txt", "d.txt"])
            XCTAssertTrue(listing.entries.allSatisfy(\.isEncrypted))
            let report = try BoltArchiveEngine.testIntegrity(archiveURL: archive, password: "password")
            XCTAssertTrue(report.isHealthy)
            XCTAssertEqual(report.passedCount, 4)

            let destination = root.appendingPathComponent("\(fixture.rawValue)-extracted", isDirectory: true)
            try BoltArchiveEngine.extract(archiveURL: archive,
                                          options: ExtractOptions(destinationURL: destination, mode: .here, password: "password"))
            for entry in listing.entries {
                XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(entry.path)), payload(for: entry.path))
            }
        }
    }

    func testContentEncryptedRAR4AndRAR5OpenWithPerEntryPasswords() throws {
        for fixture in [RARFixture.encryptedDataRAR4, .encryptedDataRAR5] {
            let archive = try writeArchive(fixture)
            let listing = try BoltArchiveEngine.inspect(archiveURL: archive)
            XCTAssertEqual(listing.entries.filter(\.isEncrypted).map(\.path), ["b.txt", "d.txt"])
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "a.txt"), payload(for: "a.txt"))
            XCTAssertThrowsError(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "b.txt")) { error in
                guard case BoltZipError.passwordRequired = error else { return XCTFail("\(fixture): \(error)") }
            }
            XCTAssertThrowsError(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "d.txt", password: "password")) { error in
                guard case BoltZipError.wrongPassword = error else { return XCTFail("\(fixture): \(error)") }
            }
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "b.txt", password: "password"),
                           payload(for: "b.txt"))
            XCTAssertEqual(try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "d.txt", password: "password2"),
                           payload(for: "d.txt"))

            let destination = root.appendingPathComponent("\(fixture.rawValue)-existing", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let oldFile = destination.appendingPathComponent("a.txt")
            let oldBytes = Data("already there".utf8)
            try oldBytes.write(to: oldFile)
            // The password decrypts b.txt but fails on d.txt. No earlier entry should be published.
            XCTAssertThrowsError(try BoltArchiveEngine.extract(
                archiveURL: archive, options: ExtractOptions(destinationURL: destination, mode: .here,
                                                              overwritePolicy: .overwrite, password: "password")
            )) { error in
                guard case BoltZipError.wrongPassword = error else { return XCTFail("\(fixture): \(error)") }
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["a.txt"])
            XCTAssertEqual(try Data(contentsOf: oldFile), oldBytes)

            try BoltArchiveEngine.extract(
                archiveURL: archive, options: ExtractOptions(destinationURL: destination, mode: .selected(["d.txt"]), password: "password2")
            )
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("d.txt")), payload(for: "d.txt"))
        }
    }

    func testLegacySolidRARPreviewsAndExtractsTheSecondFile() throws {
        let archive = try writeArchive(.solidRAR3)
        let listing = try BoltArchiveEngine.inspect(archiveURL: archive)
        XCTAssertEqual(listing.entries.map(\.path), ["stest1.txt", "stest2.txt"])
        let data = try BoltArchiveEngine.readEntryData(archiveURL: archive, entryPath: "stest2.txt")
        XCTAssertEqual(data.count, 2048)
        XCTAssertEqual(CompressionCodec.crc32(data), 0xC5B7E6A2)

        let preview = root.appendingPathComponent("preview.txt")
        try BoltArchiveEngine.extractSingleEntryToFile(archiveURL: archive, entryPath: "stest2.txt", destinationFileURL: preview)
        XCTAssertEqual(try Data(contentsOf: preview), data)

        let destination = root.appendingPathComponent("solid", isDirectory: true)
        try BoltArchiveEngine.extract(archiveURL: archive, options: ExtractOptions(destinationURL: destination, mode: .here))
        for entry in listing.entries {
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(entry.path)), data)
        }
        let report = try BoltArchiveEngine.testIntegrity(archiveURL: archive)
        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.passedCount, 2)
    }

    private func writeArchive(_ fixture: RARFixture) throws -> URL {
        let archive = root.appendingPathComponent(fixture.rawValue).appendingPathExtension("rar")
        let data = try XCTUnwrap(Data(base64Encoded: fixture.base64, options: .ignoreUnknownCharacters))
        try data.write(to: archive)
        return archive
    }

    private func payload(for name: String) -> Data { Data("This is from \(name)".utf8) }
}

// The solid archive is rarfile's test/files/rar3-solid.rar, release v4.2.
// https://github.com/markokr/rarfile/tree/v4.2/test/files
//
// Copyright (c) 2005-2024 Marko Kreen <markokr@gmail.com>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//
// The encrypted archives are libarchive's test_read_format_rar{4,5}_encrypted
// and test_read_format_rar{4,5}_encrypted_filenames fixtures, release v3.8.1.
// https://github.com/libarchive/libarchive/tree/v3.8.1/libarchive/test
/*
 * Copyright (c) 2003-2018
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
private enum RARFixture: String {
    case solidRAR3
    case encryptedNamesRAR4
    case encryptedNamesRAR5
    case encryptedDataRAR4
    case encryptedDataRAR5

    var base64: String {
        switch self {
        case .solidRAR3:
            """
            UmFyIRoHADvQcwgADQAAAAAAAAArNHSAkCwAXAAAAAAIAAADoua3xbBmzD4dMwoApIEAAHN0ZXN0
            MS50eHQAwBEMzP6MnrD+MYGrrLG7QHeoCmTWSzeDwQe8AeCFku77th0ACCAACIjpeAzSDAdhOkF4
            S7Nun1IK2sonQLrnC2SKYnH7uACRnlAv2FX/+sZY6+vE14h+VJaHH03s2RZ0kJAsAA4AAAAACAAA
            A6Lmt8WwZsw+HTMKAKSBAABzdGVzdDIudHh0AMCxIACIB+vyCmn6/JTe0MQ9ewBABwA=
            """
        case .encryptedNamesRAR4:
            """
            UmFyIRoHAM6Zc4AADQAAAAAAAAAAAAAAAAAAAHQLhjMoMLWHQDJeY20c4vaKVtHClR72L6r0d23B
            E5Sd3EMg5SU6+Cs/bn2n8KU9GCWixDfgW04TYlx8Y8UNczV1XqthmOHsTsvvjtW98xWQjVRzOJ+H
            Wtvn/yck3YlnIAAAAAAAAAAAIiMI9vV7WRujtH8xZ7GclVkWmWAf3pADNOI9qf3+jZB1NVv+SdHw
            LVrIlk7apU0dQP6o2x7mYowi6cL3hOK0VcyErLYGPvy/8iuY2V22t9CVmaEU5a8qyMJMF9MRyb6e
            AAAAAAAAAADKiQEJRlpi77vZY9M4Qk0eoAuLGKOuuwrB9R4qDIhm/0mWQmlTBsQOR0LdpcH476Qa
            mST1/7WzOpa6uxO8go689GQsPwazhEaM5c+UOhB8zikXurV72lPZEZrPuSA7X90AAAAAAAAAAO8E
            6Tfe/6OTKeWcRSFXURfW/OPhBa4hBwCiQwzVVeLFqJNoEQ0BPPeEH9HN1f/Cvduf/azulc+VU6TP
            7YMt+mfWTWJ4v1uszUg88ugRqD6P2fqc/4zejuhSRMcxbcbj7gAAAAAAAAAA8J9Fd+s8JNpIkqv+
            eRXXow==
            """
        case .encryptedNamesRAR5:
            """
            UmFyIRoHAQCuI9KQIQQAAAEPaAuw0KfIvaHedKdxMjSbGbcKghg7J7kA48ppJRDshMehHkYtfQ41
            TsTW1krt6Tl3x7oj46TcFBvKdO5M3PzcxjhfvPaKM+6VdtWzTK5WbLTVjAZAKU39cHaXSmTHGare
            Mmi1q2J0+Rt3M4QJjUwX3IACEDNux82FP6G5qdUhXD3hLZOVH//RjmJUmafz277uR1+RWwOL0xV4
            OHCguxCdWrT6eabORj2lcFFtRNvxTsQm67rpS0z3AOSzmSQc60PMdPI3rULZC8LqGEHJ/T2Mm3Ff
            d+7tpOW7qhPeQ2V30iTNxp2cTxHfLL4EQ9f42IflyMXRjh4iusRr0VhKYKGL0gW9h/JKrh9F2TzM
            QibzIs3R2OhoO1W1Qu8NFBgqZxNmqF+HvJIqyVLSzEVqvP4hT3Utzq7ySXFw/UEnh3z3BzzIUph/
            NJ6a7af2VkBmg0nnZsQBR0m7ahocZnQO7HFXN8aeCGIY5D6DWSb1OaMTLdcElWzYjQSp7Pcv6ene
            NTwR5cHq3/mqP92qNxXphWUcfAbn03co9gd5zQJzK8fzr4xEoO5Bc6rA7R7f6I8I/89e1a/0rPlo
            ttbw3qfTA5ZzWGFWsg0QN1cGUl7L/me6FLrm3HG3eAMOd9Dzpbh75hJbutWAVrQRq9gp0WvY3DB9
            OhEF/Vt8l9zQGckAC0MaoXeO0vwijsZEjCn1Sc3Jx8ZhiqsoVXcEDbGFc+uDNu7VrlfAVWM3zonc
            n1UBBOLg61LVu8bq7XqNKKyD28RZcpbv7pFfNQQS1MYyEO+tPwY39fSWuL2iVN8iDXbz2b/sDFUw
            xTWwi00menGYlJJgOoQRxagRx+O525pnIfDSazWQUk8Hj31OBaNlAdbU2mzLr1ssqcSngnENtmV2
            XS055B91I1iUXTvfA1Hd3HDk8UhFzN/mfPg9zJt1eO72RA==
            """
        case .encryptedDataRAR4:
            """
            UmFyIRoHAM+QcwAADQAAAAAAAAAqY3QgkCoAEgAAABIAAAACVW5a7mRXdlgdMAUAIAAAAGEudHh0
            APD8TBtUaGlzIGlzIGZyb20gYS50eHRfjnQklDIAIAAAABIAAAAChRT6qWdXdlgdMwUAIAAAAGIu
            dHh0vgIbmnkqilUAsHKgNMn59g0Qf6jR1nzr1KS2yNRrgooen66wDfjatsdECurku8d0IJAqABIA
            AAASAAAAAjU9mpRuV3ZYHTAFACAAAABjLnR4dACwPkgtVGhpcyBpcyBmcm9tIGMudHh07cp0JJQy
            ACAAAAASAAAAAiXhuiZNZHZYHTMFACAAAABkLnR4dK/ifRPzpVNSAPD7YY92+D/JR2gbUC02jMB4
            ydOpRar2iQPcvhjgjGZX2wT16cQ9ewBABwA=
            """
        case .encryptedDataRAR5:
            """
            UmFyIRoHAQAzkrXlCgEFBgAFAQGAgAA1/zIeHwIDCxIEEiBVblrugAAABWEudHh0CgMCfCGEo4J8
            2gFUaGlzIGlzIGZyb20gYS50eHR6QXGzUAIDPDAEEiAYRaMCgAMABWIudHh0MAEAAw/HRF7hgPi1
            n9YrQzcIvFfN+jTfBqtdBdSTB3cPHY6AU+o1Zx1w8S1La5wanAoDAnJlmKaCfNoBY7pUstAQpUlf
            tLrTwGmoOxu8uzgn14eTeHMvfJPi0ijEAN7+psA7fmxn1AVQANz4jXzxZh8CAwsSBBIgNT2alIAA
            AAVjLnR4dAoDAj5I6a6CfNoBVGhpcyBpcyBmcm9tIGMudHh07P3wXVICAzygAASSACDD32MSgAMA
            BWQudHh0MAEAAw/HRF7hgPi1n9YrQzcIvFfN883Wsxy0W6d8rDZYjrMOaYNM1EjpFevWrHe3owoD
            AnvFKfSPfNoB22ly9PZWjqb9GWXplbM2hTQ39Sqg0yeHsvXBAjLYql4dd1ZRAwUEAA==
            """
        }
    }
}
