import XCTest

/// The privacy page's promise that SignalLadder's own code makes no network connection,
/// held by the page's own search.
///
/// `docs/privacy.md`, under "What it never does", gives a search of `Sources` that must
/// print nothing. These tests read the pattern from the page, so the page and the test
/// cannot drift, and run it over every file under `Sources`, as the search does, line by
/// line. They show that the source names no networking API, not what Apple's frameworks
/// do at run time, which the page says too.
///
/// The button beneath Settings' version line opens a page through `NSWorkspace`, which is
/// not in the pattern: the browser makes that connection, at the user's click.
final class NoNetworkTests: XCTestCase {
    private static let root = PackageRoot.url

    /// What the pattern names today. The page may add to it, and a test fails if it
    /// drops one.
    private static let namedToday = ["URLSession", "URLRequest", "NWConnection", "CFNetwork", "WebKit", "Sparkle",
                                     "import Network"]

    /// The pattern of the search under "What it never does", as the page writes it
    /// between the single quotes of `grep -rnE '…' Sources`. There must be exactly one
    /// such line in that section.
    static func pageSearchPattern() throws -> String {
        let page = try String(contentsOf: root.appendingPathComponent("docs/privacy.md"), encoding: .utf8)
        let lines = page.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex(of: "## What it never does"),
                                  "docs/privacy.md has no section headed \"## What it never does\"")
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.endIndex
        let prefix = "grep -rnE '"
        let suffix = "' Sources"
        let searches = lines[start..<end].filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
        XCTAssertEqual(searches.count, 1, "the section gives one search of Sources: \(searches)")
        let search = try XCTUnwrap(searches.first, "the section gives no search of Sources")
        let pattern = String(search.dropFirst(prefix.count).dropLast(suffix.count))
        XCTAssertFalse(pattern.isEmpty)
        return pattern
    }

    /// Each line of `text` the pattern matches, as grep prints it: "line: text".
    static func matches(of pattern: String, in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        return text.components(separatedBy: "\n").enumerated().compactMap { index, line in
            let range = NSRange(line.startIndex..., in: line)
            return regex.firstMatch(in: line, range: range) == nil ? nil : "\(index + 1): \(line)"
        }
    }

    func testThePagesSearchNamesEveryNetworkingAPIItNamedWhenThisTestWasWritten() throws {
        let alternatives = Set(try Self.pageSearchPattern().components(separatedBy: "|"))
        for name in Self.namedToday {
            XCTAssertTrue(alternatives.contains(name), "the privacy page's search no longer names \(name)")
        }
    }

    /// The pattern is read as grep reads it: case-sensitive, a line at a time. It finds
    /// each name it holds, and not the call that opens the latest release's page.
    func testThePatternFindsEachNameItHoldsAndNotTheCallThatOpensAPageInTheBrowser() throws {
        let pattern = try Self.pageSearchPattern()
        for line in ["let session = URLSession.shared", "var request = URLRequest(url: url)", "let c = NWConnection(to: e, using: .tcp)",
                     "import CFNetwork", "import WebKit", "import Sparkle", "import Network"] {
            XCTAssertEqual(try Self.matches(of: pattern, in: line).count, 1, line)
        }
        for line in ["NSWorkspace.shared.open(SettingsText.latestReleaseURL)",
                     "public static let latestReleaseURL = URL(string: \"https://github.com/JWhite212/SignalLadder/releases/latest\")!",
                     "let session = urlsession"] {
            XCTAssertEqual(try Self.matches(of: pattern, in: line), [], line)
        }
    }

    /// The search prints nothing: no file under `Sources` names a networking API. Every
    /// file is read, as `grep -r` reads them, and today every one is Swift.
    func testNoFileUnderSourcesMatchesThePrivacyPagesSearch() throws {
        let pattern = try Self.pageSearchPattern()
        let sources = Self.root.appendingPathComponent("Sources")
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: [.isRegularFileKey]))
        var files: [URL] = []
        for case let file as URL in walk {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files.append(file) }
        }
        XCTAssertGreaterThan(files.count, 100, "found only \(files.count) files at \(sources.path)")
        let names = Set(files.map(\.lastPathComponent))
        for deep in ["SettingsModel.swift", "SettingsText.swift", "AXBannerWatcher.swift", "ShortcutRunner.swift"] {
            XCTAssertTrue(names.contains(deep), "the walk reached \(deep)")
        }

        var found: [String] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            let path = file.path.replacingOccurrences(of: Self.root.path + "/", with: "")
            found += try Self.matches(of: pattern, in: text).map { "\(path):\($0)" }
        }
        XCTAssertEqual(found, [], "SignalLadder's own code names a networking API, which docs/privacy.md promises it does not")
    }
}
