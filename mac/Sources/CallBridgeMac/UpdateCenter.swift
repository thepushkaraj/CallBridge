import AppKit
import Foundation

/// GitHub-Releases-backed update check + download + install for the Mac app.
/// The repo must have a published release whose assets include the .app zip.
enum MacUpdateCenter {
    static let repoSlug = "thepushkaraj/CallBridge"
    private static let api = "https://api.github.com/repos/thepushkaraj/CallBridge/releases/latest"

    struct Update {
        let version: String
        let zipURL: URL
    }

    enum CheckOutcome {
        case upToDate                    // 200 with no newer release, or no releases published yet
        case available(Update)
        case failed                      // network error or unexpected response
    }

    /// Semantic compare of dotted versions, e.g. 0.3.0 vs 0.2.2.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let trimmed = v.hasPrefix("v") ? String(v.dropFirst()) : v
            return trimmed.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        }
        let a = parts(candidate)
        let b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.0.0"
    }

    /// Fetches the latest release info; completion runs on the main queue.
    static func check(completion: @escaping (CheckOutcome) -> Void) {
        // CALLBRIDGE_UPDATE_API overrides the endpoint for local testing or a
        // self-hosted manifest; the manifest is GitHub-Releases-shaped JSON.
        let endpoint = ProcessInfo.processInfo.environment["CALLBRIDGE_UPDATE_API"] ?? api
        guard let url = URL(string: endpoint) else {
            DispatchQueue.main.async { completion(.failed) }
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            var outcome = CheckOutcome.failed
            defer { DispatchQueue.main.async { completion(outcome) } }

            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200, let data else {
                // 404 = the repo has no published releases yet; the running
                // install is then the newest that exists.
                outcome = (status == 404) ? .upToDate : .failed
                return
            }
            guard
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = root["tag_name"] as? String
            else { return }

            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isNewer(version, than: currentVersion()),
                  let assets = root["assets"] as? [[String: Any]]
            else {
                outcome = .upToDate
                return
            }

            let zip = assets.first {
                ($0["name"] as? String)?.hasSuffix(".zip") == true
            }.flatMap { $0["browser_download_url"] as? String }
            guard let zipURLString = zip, let zipURL = URL(string: zipURLString) else {
                outcome = .upToDate
                return
            }

            outcome = .available(Update(version: version, zipURL: zipURL))
        }.resume()
    }

    /// Swaps the running bundle with the downloaded one and relaunches.
    /// A detached helper script performs the swap one second after the app exits.
    static func installDownloadedUpdate() {
        guard
            let zip = cachedUpdateZip(),
            let appPath = Bundle.main.bundlePath as String?
        else { return }

        let script = """
        #!/bin/bash
        sleep 1
        WORK="$(mktemp -d)"
        /usr/bin/ditto -x -k "\(zip.path)" "$WORK"
        rm -rf "\(appPath)"
        mv "$WORK/CallBridge.app" "\(appPath)"
        rm -rf "$WORK" "\(zip.path)"
        open "\(appPath)"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("callbridge-update.sh")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try? process.run()

        // Quit so the helper can finish the swap and relaunch the new version.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    static func cachedUpdateZip() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CallBridge-macOS.zip")
        return (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil ? url : nil
    }
}

/// Single-use download session with progress callbacks. Owned by AppState.
final class UpdateDownloader: NSObject, URLSessionDownloadDelegate {
    private var session: URLSession?
    private var finished = false
    var onProgress: ((Double) -> Void)?
    var onComplete: ((URL?) -> Void)?

    func download(from url: URL) {
        finished = false
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session?.downloadTask(with: url).resume()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.onProgress?(fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("CallBridge-macOS.zip")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finished = true
            DispatchQueue.main.async {
                self.onProgress?(1)
                self.onComplete?(destination)
            }
        } catch {
            DispatchQueue.main.async { self.onComplete?(nil) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil, !finished {
            DispatchQueue.main.async { self.onComplete?(nil) }
        }
    }
}
