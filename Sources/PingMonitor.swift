import Foundation

struct PingResult {
    let timestamp: Date
    let latencyMs: Double?  // nil means timeout/loss
}

struct PingStats {
    let packetLossPercent: Double
    let avgMs: Double
    let minMs: Double
    let maxMs: Double
    let sampleCount: Int
}

final class PingMonitor {
    var windowPackets: Int = 10 {
        didSet { results.removeAll() }
    }
    private var results: [PingResult] = []
    private var timer: Timer?
    private var currentProcess: Process?

    var target: String = "google.com" {
        didSet { results.removeAll() }
    }

    var onChange: ((PingStats) -> Void)?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
        sendPing()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentProcess?.terminate()
        currentProcess = nil
    }

    private func sendPing() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-W", "2000", self.target]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                self.recordResult(latencyMs: nil)
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus == 0,
               let range = output.range(of: "time="),
               let endRange = output.range(of: " ms", range: range.upperBound..<output.endIndex) {
                let timeStr = String(output[range.upperBound..<endRange.lowerBound])
                let latency = Double(timeStr)
                self.recordResult(latencyMs: latency)
            } else {
                self.recordResult(latencyMs: nil)
            }
        }
    }

    private func recordResult(latencyMs: Double?) {
        let result = PingResult(timestamp: Date(), latencyMs: latencyMs)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.results.append(result)

            // Keep only the last N packets
            if self.results.count > self.windowPackets {
                self.results.removeFirst(self.results.count - self.windowPackets)
            }

            guard !self.results.isEmpty else { return }

            let total = self.results.count
            let lost = self.results.filter { $0.latencyMs == nil }.count
            let packetLoss = Double(lost) / Double(total) * 100.0

            let successful = self.results.compactMap { $0.latencyMs }
            let avgLatency = successful.isEmpty ? 2000.0 : successful.reduce(0, +) / Double(successful.count)
            let minLatency = successful.min() ?? 0
            let maxLatency = successful.max() ?? 0

            let stats = PingStats(
                packetLossPercent: packetLoss,
                avgMs: avgLatency,
                minMs: minLatency,
                maxMs: maxLatency,
                sampleCount: total
            )
            self.onChange?(stats)
        }
    }
}
