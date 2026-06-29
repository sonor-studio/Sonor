import Foundation

// We can't easily import Hub without a full SPM project, but we can simulate the HF HEAD requests.
let session = URLSession.shared
let filenames = [".gitattributes", "README.md", "chat_template.jinja", "config.json", "generation_config.json", "model.safetensors", "model.safetensors.index.json", "processor_config.json", "tokenizer.json", "tokenizer_config.json"]

let group = DispatchGroup()
var totalSize: Int64 = 0

for filename in filenames {
    group.enter()
    let url = URL(string: "https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/main/\(filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    let task = session.dataTask(with: request) { data, response, error in
        if let response = response as? HTTPURLResponse {
            let size = Int64(response.value(forHTTPHeaderField: "Content-Length") ?? response.value(forHTTPHeaderField: "x-linked-size") ?? "0") ?? 0
            totalSize += size
        }
        group.leave()
    }
    task.resume()
}

group.wait()
