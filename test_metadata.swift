import Foundation
import Hub

async func test() {
    do {
        let repoId = "mlx-community/gemma-3-4b-it-qat-4bit"
        let globs = ["*.safetensors", "*.json", "*.jinja"]
        let metadatas = try await HubApi.getFileMetadata(from: repoId, matching: globs)
        var totalSize = 0
        for md in metadatas {
            print("\(md.path): \(md.size ?? -1)")
            totalSize += md.size ?? 0
        }
        print("Total size: \(totalSize)")
    } catch {
        print("Error: \(error)")
    }
}

Task {
    await test()
    exit(0)
}
RunLoop.main.run()
