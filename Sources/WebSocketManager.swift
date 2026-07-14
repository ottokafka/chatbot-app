import Foundation

final class WebSocketManager: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private let urlString: String
    
    var onMessageReceived: ((String) -> Void)?
    var onConnectionStateChange: ((Bool) -> Void)?
    var onLog: ((String) -> Void)?
    var onError: ((String) -> Void)?
    
    private(set) var isConnected = false
    
    init(urlString: String) {
        self.urlString = urlString
        super.init()
    }
    
    func connect() {
        guard !isConnected else { return }
        
        guard let url = URL(string: urlString) else {
            onLog?("WebSocketManager: Invalid URL format '\(urlString)'.")
            onError?("Invalid WebSocket URL.")
            return
        }
        
        onLog?("WebSocketManager: Connecting to \(urlString)...")
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        listen()
    }
    
    func disconnect() {
        onLog?("WebSocketManager: Disconnecting.")
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session = nil
        setConnected(false)
    }
    
    func sendAudio(data: Data) {
        guard isConnected else { return }
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                self?.onLog?("WebSocketManager: Error sending audio chunk: \(error.localizedDescription)")
            }
        }
    }

    /// Sends a UTF-8 text frame (JSON control messages for pronunciation assessment, etc.).
    func sendText(_ text: String) {
        guard isConnected else {
            onLog?("WebSocketManager: sendText skipped — not connected.")
            return
        }
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                self?.onLog?("WebSocketManager: Error sending text: \(error.localizedDescription)")
                self?.onError?("WebSocket send failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.onLog?("WebSocketManager: Received text message: \(text)")
                    self.onMessageReceived?(text)
                case .data(let data):
                    self.onLog?("WebSocketManager: Received binary data message of length \(data.count) (ignored).")
                @unknown default:
                    break
                }
                // Continue listening
                self.listen()
            case .failure(let error):
                // Only log if we didn't initiate disconnect
                if self.webSocketTask != nil {
                    self.onLog?("WebSocketManager: Receive failed with error: \(error.localizedDescription)")
                    self.setConnected(false)
                }
            }
        }
    }
    
    private func setConnected(_ connected: Bool) {
        guard isConnected != connected else { return }
        isConnected = connected
        onConnectionStateChange?(connected)
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onLog?("WebSocketManager: Connection successfully opened.")
        setConnected(true)
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        var reasonString = ""
        if let reason = reason {
            reasonString = String(data: reason, encoding: .utf8) ?? ""
        }
        onLog?("WebSocketManager: Connection closed. Code: \(closeCode.rawValue), Reason: \(reasonString)")
        setConnected(false)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onLog?("WebSocketManager: Task completed with error: \(error.localizedDescription)")
            onError?("WebSocket connection error: \(error.localizedDescription)")
            setConnected(false)
        }
    }
}
