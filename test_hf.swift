import Foundation

let url = URL(string: "https://huggingface.co/api/models/mlx-community/gemma-4-e2b-it-4bit/paths-info/main")!
var request = URLRequest(url: url)
let task = URLSession.shared.dataTask(with: request) { data, response, error in
    if let data = data {
    }
}
task.resume()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
