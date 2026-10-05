// Sources/NotificationCore/BuildInfo.swift
import Foundation

/// Which build is running, as the bundle's property list says it (M5 plan, O12,
/// Task 6).
///
/// Two builds of the same release number can differ by a fix, and on 2026-10-02
/// a build from before a capture fix was run without anyone knowing it, because
/// both said 0.1.0. So `Scripts/make-app.sh` writes three more keys into the
/// staged copy of `Info.plist`, before it signs, since the signature seals the
/// file:
///
/// - `SLBuildCommit`, the commit's short hash;
/// - `SLBuildDate`, the time of the build in UTC, as `2026-10-05T10:51:08Z`;
/// - `SLBuildModified`, a Boolean, true when `git status` lists changes to the
///   files git tracks that were not committed. A new file git does not track yet
///   is not counted, though the build compiles it, so a line that does not say
///   "with local changes" is no claim that the build is exactly that commit.
///
/// Outside a git checkout it writes none of them, and `Resources/Info.plist`
/// itself carries none, so the repository holds no build's details. The app
/// target hands `Bundle.main.infoDictionary` to `init(infoDictionary:)` and
/// shows what `SettingsText.version(_:date:)` makes of it.
///
/// **Every value is optional, and none is guessed.** A build with no stamp (one
/// made by `swift run`, or from a source archive) reads as no commit, and a value
/// that is not what the script writes reads as not recorded: a date that does not
/// parse, a Boolean that is not one, text that is empty. A modified key that is
/// absent or is not a Boolean is nil, which is not the same as false: false is
/// the stamp saying the tracked files were unchanged. Nothing here can fail, and
/// nothing says more than the dictionary did.
public struct BuildInfo: Equatable, Sendable {
    /// The release number, `CFBundleShortVersionString`.
    public let version: String?
    /// The build number, `CFBundleVersion`.
    public let buildNumber: String?
    /// The short hash of the commit the build was made from.
    public let commit: String?
    /// When the build was made, nil when it was not recorded or did not parse.
    public let date: Date?
    /// What the stamp says about changes to the tracked files that were not
    /// committed: true or false when `SLBuildModified` is a Boolean, and nil when
    /// the key is absent or is not one, which is the stamp saying nothing. The
    /// line says "with local changes" for true and nothing about changes for
    /// false or nil.
    public let modified: Bool?

    public init(version: String?, buildNumber: String?, commit: String?, date: Date?, modified: Bool?) {
        self.version = version
        self.buildNumber = buildNumber
        self.commit = commit
        self.date = date
        self.modified = modified
    }

    // MARK: - The keys

    /// The two keys the bundle always has, from `Resources/Info.plist`.
    public static let versionKey = "CFBundleShortVersionString"
    public static let buildNumberKey = "CFBundleVersion"
    /// The three keys `Scripts/make-app.sh` adds to the staged copy. A test reads
    /// the script and holds it to these names.
    public static let commitKey = "SLBuildCommit"
    public static let dateKey = "SLBuildDate"
    public static let modifiedKey = "SLBuildModified"

    // MARK: - Reading

    /// What the dictionary says, which may be nothing: `Bundle.main.infoDictionary`
    /// is itself optional, and is handed over as it comes.
    public init(infoDictionary: [String: Any]?) {
        let info = infoDictionary ?? [:]
        self.init(version: Self.text(info[Self.versionKey]),
                  buildNumber: Self.text(info[Self.buildNumberKey]),
                  commit: Self.text(info[Self.commitKey]),
                  date: Self.date(fromStamp: info[Self.dateKey]),
                  modified: Self.flag(info[Self.modifiedKey]))
    }

    /// A string with something in it. Spaces round it are not part of it, and a
    /// string of nothing else is not recorded; so is a value that is not a string.
    public static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The time a stamp names, or nil.
    ///
    /// The script writes UTC in one shape, `2026-10-05T10:51:08Z`, and that is the
    /// only shape read. The system's reader on its own is generous: it takes a
    /// 30th of February as the 2nd of March and ignores what follows the zone, so
    /// the date it gave back would be one the stamp never named. So what it
    /// returns is written out again and must come back as the same text, which
    /// refuses a day or an hour that does not exist, other spellings of a valid
    /// time, and anything with extra characters.
    public static func date(fromStamp value: Any?) -> Date? {
        guard let stamp = value as? String else { return nil }
        let reader = ISO8601DateFormatter()
        guard let date = reader.date(from: stamp), reader.string(from: date) == stamp else { return nil }
        return date
    }

    /// What a Boolean says, or nil for a value that is not one. The number 1 and
    /// the text "true" are not what the script writes, and are not read as it:
    /// they are nil, and so is no value at all.
    public static func flag(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
