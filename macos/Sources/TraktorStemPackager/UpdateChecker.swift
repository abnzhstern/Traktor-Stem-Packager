import AppKit
import Combine
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let offersDownload: Bool
    }

    @Published var notice: Notice?

    static let latestReleaseURL = URL(string: "https://github.com/abnzhstern/Traktor-Stem-Packager/releases/latest")!

    private let endpoint = URL(string: "https://api.github.com/repos/abnzhstern/Traktor-Stem-Packager/releases/latest")!
    private let lastCheckKey = "TraktorStemPackagerLastUpdateCheck"
    private let checkInterval: TimeInterval = 24 * 60 * 60

    func checkAutomatically() async {
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < checkInterval {
            return
        }
        await check(reportCurrentVersion: false, reportErrors: false)
    }

    func checkManually() {
        Task { await check(reportCurrentVersion: true, reportErrors: true) }
    }

    func openLatestRelease() {
        NSWorkspace.shared.open(Self.latestReleaseURL)
    }

    private func check(reportCurrentVersion: Bool, reportErrors: Bool) async {
        do {
            var request = URLRequest(url: endpoint)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Traktor-Stem-Packager", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 12

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateError.unavailable
            }

            let release = try JSONDecoder().decode(Release.self, from: data)
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let available = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            if available.compare(installed, options: .numeric) == .orderedDescending {
                notice = Notice(
                    title: "Update Available",
                    message: "Traktor Stem Packager \(available) is available. You have version \(installed).",
                    offersDownload: true
                )
            } else if reportCurrentVersion {
                notice = Notice(
                    title: "You’re Up to Date",
                    message: "Traktor Stem Packager \(installed) is the latest version.",
                    offersDownload: false
                )
            }
        } catch {
            if reportErrors {
                notice = Notice(
                    title: "Couldn’t Check for Updates",
                    message: "The latest release could not be reached. Check your internet connection and try again.",
                    offersDownload: false
                )
            }
        }
    }

    private struct Release: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }

    private enum UpdateError: Error {
        case unavailable
    }
}
