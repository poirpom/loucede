//
//  UpdateChecker.swift
//  loucede
//
//  Vérifie les mises à jour via GitHub Releases.
//

import Foundation
import AppKit
import Combine

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadURL: String?
    @Published var errorMessage: String?

    // GitHub API URL for latest release
    private let githubReleasesURL = "https://api.github.com/repos/poirpom/loucede/releases/latest"

    // Current app version from bundle
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func checkForUpdates() {
        isChecking = true
        updateAvailable = false
        errorMessage = nil

        guard let url = URL(string: githubReleasesURL) else {
            errorMessage = "Invalid URL"
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false

                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }

                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Get tag name (version)
                        if let tagName = json["tag_name"] as? String {
                            // Remove 'v' prefix if present
                            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                            self?.latestVersion = version

                            // Compare versions
                            if self?.isNewerVersion(version, than: self?.currentVersion ?? "0") == true {
                                self?.updateAvailable = true

                                // Get download URL from assets
                                if let assets = json["assets"] as? [[String: Any]],
                                   let firstAsset = assets.first,
                                   let downloadURL = firstAsset["browser_download_url"] as? String {
                                    self?.downloadURL = downloadURL
                                } else if let htmlURL = json["html_url"] as? String {
                                    // Fallback to release page
                                    self?.downloadURL = htmlURL
                                }
                            }
                        }
                    }
                } catch {
                    self?.errorMessage = "Failed to parse response"
                }
            }
        }.resume()
    }

    func openDownloadPage() {
        // Ouvre la page de releases GitHub ou l'URL d'asset détectée
        let fallback = "https://github.com/poirpom/loucede/releases/latest"
        let target = downloadURL ?? fallback
        if let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        }
    }

    // Compare semantic versions (e.g., "1.2.3" vs "1.2.4")
    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newComponents = new.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(newComponents.count, currentComponents.count)

        for i in 0..<maxLength {
            let newValue = i < newComponents.count ? newComponents[i] : 0
            let currentValue = i < currentComponents.count ? currentComponents[i] : 0

            if newValue > currentValue {
                return true
            } else if newValue < currentValue {
                return false
            }
        }

        return false
    }
}
