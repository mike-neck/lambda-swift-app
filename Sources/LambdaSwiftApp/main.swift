import Foundation

extension Data {
    var asString: String? {
        get {
            return String(data: self, encoding: .utf8)
        }
    }
}

extension URL {
    var request: URLRequest {
        return URLRequest(url: self)
    }
}

struct RuntimeApi {
    let hostPort: String

    var nextInvocation: URL {
        if let url = URL(string: "http://\(hostPort)/runtime/invocation/next") {
            return url
        }
        exit(1)
    }

    func invocationResponse(for requestId: String) -> URL {
        if let url = URL(string: "http://\(hostPort)/runtime/invocation/\(requestId)/response") {
            return url
        }
        exit(1)
    }
}

enum HttpResp {
    case httpResponse(json: String, response: HTTPURLResponse)
    case error(_: Error)
}

struct HttpRespError: Error {
    let message: String
}

extension HttpResp {
    init(data: Data?, response: URLResponse?, error: Error?) {
        if let err = error {
            self = .error(err)
        }
        let json: String = {
            guard let d = data?.asString else {
                return ""
            }
            return d
        }()
        guard let res = response as? HTTPURLResponse else {
            self = .error(HttpRespError(message: "response is nil"))
            return
        }
        self = .httpResponse(json: json, response: res)
    }
}

extension HttpResp {
    func payload(api: RuntimeApi) -> (String, String)? {
        switch self {
        case .error(let err):
            print("request to \(api.nextInvocation) was failed. \(err)")
            return nil
        case .httpResponse(let json, let res):
            guard let requestId = res.allHeaderFields["Lambda-Runtime-Aws-Request-Id"] as? String else {
                print("Header Lambda-Runtime-Aws-Request-Id not found.")
                return nil
            }
            return (requestId, json)
        }
    }
}

extension URLSession {
    func get(_ url: URL, _ handler: @escaping (HttpResp) -> ()) -> URLSessionDataTask {
        return self.dataTask(with: url, completionHandler: { (data: Data?, response: URLResponse?, err: Error?) in handler(HttpResp(data: data, response: response, error: err)) })
    }

    func post(_ url: URL, _ json: String, _ handler: @escaping (HttpResp) -> ()) -> URLSessionDataTask {
        var req = url.request
        req.httpBody = json.data(using: .utf8)
        return self.dataTask(with: req, completionHandler: { (data: Data?, response: URLResponse?, err: Error?) in handler(HttpResp(data: data, response: response, error: err)) })
    }
}

extension String {
    var asRuntimeApi: RuntimeApi {
        return RuntimeApi(hostPort: self)
    }
}

guard let api = ProcessInfo.processInfo.environment["AWS_LAMBDA_RUNTIME_API"]?.asRuntimeApi else {
    print("AWS_LAMBDA_RUNTIME_API is not defined.")
    exit(1)
}

let client = URLSession.shared

while true {
    let semaphore = DispatchSemaphore(value: 0)
    client.get(api.nextInvocation) { (response: HttpResp) in
        guard let (id, payload) = response.payload(api: api) else {
            exit(2)
        }
        let responsePayload = "{\"receive\":\(payload)}"
        client.post(api.invocationResponse(for: id), responsePayload) { (res: HttpResp) in
            print("\(res)")
            semaphore.signal()
        }.resume()
        semaphore.signal()
    }.resume()
    semaphore.wait()
    semaphore.wait()
}
