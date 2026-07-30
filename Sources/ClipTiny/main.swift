import AppKit

if CommandLine.arguments.contains("--verify-keychain") {
    do {
        _ = try KeychainKeyStore.loadOrCreateKey()
        print("ClipTiny keychain: OK")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("ClipTiny keychain: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
