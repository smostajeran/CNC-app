import Foundation

/// App version + git tip.
/// `gitCommit` is stamped by `scripts/stamp-build-info.sh` before each Mac build, then restored to `unknown`.
enum BuildInfo {
    /// Keep in sync with `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in project.yml.
    static let marketingVersionFallback = "1.3"
    static let buildNumberFallback = "4"

    /// Stamped short SHA at compile time (or `"unknown"` in the repo source tree).
    static let gitCommit = "2abb47b"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? marketingVersionFallback
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? buildNumberFallback
    }

    /// Prefer Info.plist `QuillGitCommit` (post-build stamp), else compile-time stamp.
    static var resolvedGitCommit: String {
        if let plist = Bundle.main.object(forInfoDictionaryKey: "QuillGitCommit") as? String,
           !plist.isEmpty, plist != "unknown" {
            return plist
        }
        return gitCommit
    }

    /// e.g. `1.3 (4) · 2abb47b`
    static var displayLabel: String {
        "\(shortVersion) (\(buildNumber)) · \(resolvedGitCommit)"
    }
}
