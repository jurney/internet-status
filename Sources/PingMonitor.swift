import Foundation
import Darwin

enum PingOutcome {
    case success(latencyMs: Double)
    case timeout
    case dnsFailure
}

struct PingResult {
    let outcome: PingOutcome
}

struct PingStats {
    let packetLossPercent: Double
    let avgMs: Double
    let minMs: Double
    let maxMs: Double
    let sampleCount: Int
    let dnsFailure: Bool
}

// ICMP packet structures
private struct ICMPHeader {
    var type: UInt8
    var code: UInt8
    var checksum: UInt16
    var identifier: UInt16
    var sequenceNumber: UInt16
}

private let icmpEchoRequest: UInt8 = 8
private let icmpEchoReply: UInt8 = 0
private let icmpHeaderSize = MemoryLayout<ICMPHeader>.size
private let ipHeaderMinSize = 20

final class PingMonitor {
    var windowPackets: Int = 10 {
        didSet {
            DispatchQueue.main.async { self.results.removeAll() }
        }
    }
    private var results: [PingResult] = []
    private var timer: Timer?
    private var sequenceNumber: UInt16 = 0
    private let identifier: UInt16 = UInt16(ProcessInfo.processInfo.processIdentifier & 0xFFFF)

    // Track in-flight pings for cleanup
    private let maxInFlight = 2
    private var inFlightCount = 0
    private var stopped = false

    var target: String = "google.com" {
        didSet {
            DispatchQueue.main.async { self.results.removeAll() }
        }
    }

    var onChange: ((PingStats) -> Void)?

    func start() {
        stop()
        stopped = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
        sendPing()
    }

    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
        // In-flight pings on background threads will see `stopped` and bail out.
        // Their sockets will timeout (2s) and the threads will return naturally.
        // inFlightCount is only touched on main so no race.
    }

    private func sendPing() {
        guard !stopped, inFlightCount < maxInFlight else { return }
        inFlightCount += 1

        let seq = sequenceNumber
        sequenceNumber &+= 1
        let currentTarget = target
        let ident = identifier

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let outcome = Self.performPing(target: currentTarget, identifier: ident,
                                            sequenceNumber: seq)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.inFlightCount -= 1

                // Discard result if we've been stopped
                guard !self.stopped else { return }

                self.results.append(PingResult(outcome: outcome))

                if self.results.count > self.windowPackets {
                    self.results.removeFirst(self.results.count - self.windowPackets)
                }

                self.notifyChange()
            }
        }
    }

    // Stateless, self-contained ping — runs entirely on the calling thread,
    // owns its own socket, and always cleans up before returning.
    private static func performPing(target: String, identifier: UInt16,
                                     sequenceNumber: UInt16) -> PingOutcome {
        // Resolve hostname (use SOCK_STREAM for getaddrinfo — ICMP hints are rejected)
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var infoPtr: UnsafeMutablePointer<addrinfo>?
        let resolveResult = getaddrinfo(target, nil, &hints, &infoPtr)
        guard resolveResult == 0, let info = infoPtr else {
            if infoPtr != nil { freeaddrinfo(infoPtr) }
            return .dnsFailure
        }
        defer { freeaddrinfo(infoPtr) }

        guard let addr = info.pointee.ai_addr else { return .dnsFailure }
        let addrLen = info.pointee.ai_addrlen

        // Create ICMP socket (SOCK_DGRAM — no root required on macOS)
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return .timeout }
        defer { close(sock) }

        // Set 2-second receive timeout
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Build ICMP echo request
        var header = ICMPHeader(
            type: icmpEchoRequest,
            code: 0,
            checksum: 0,
            identifier: identifier.bigEndian,
            sequenceNumber: sequenceNumber.bigEndian
        )
        header.checksum = icmpChecksum(header: &header)

        // Send
        let sendTime = CFAbsoluteTimeGetCurrent()
        let sent = withUnsafePointer(to: &header) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: icmpHeaderSize) { buf in
                sendto(sock, buf, icmpHeaderSize, 0, addr, addrLen)
            }
        }
        guard sent == icmpHeaderSize else { return .timeout }

        // Receive — loop to skip non-matching replies
        var recvBuf = [UInt8](repeating: 0, count: 128)
        while true {
            let n = recv(sock, &recvBuf, recvBuf.count, 0)
            if n < 0 { return .timeout }  // timeout or error

            let recvTime = CFAbsoluteTimeGetCurrent()

            // Parse: IP header (variable length) + ICMP header
            guard n >= ipHeaderMinSize + icmpHeaderSize else { continue }

            // IP header length from IHL field
            let ihl = Int(recvBuf[0] & 0x0F) * 4
            guard n >= ihl + icmpHeaderSize else { continue }

            let icmpOffset = ihl
            let replyType = recvBuf[icmpOffset]
            let replyIdHi = recvBuf[icmpOffset + 4]
            let replyIdLo = recvBuf[icmpOffset + 5]
            let replySeqHi = recvBuf[icmpOffset + 6]
            let replySeqLo = recvBuf[icmpOffset + 7]

            let replyId = (UInt16(replyIdHi) << 8) | UInt16(replyIdLo)
            let replySeq = (UInt16(replySeqHi) << 8) | UInt16(replySeqLo)

            if replyType == icmpEchoReply && replyId == identifier && replySeq == sequenceNumber {
                let latencyMs = (recvTime - sendTime) * 1000.0
                return .success(latencyMs: latencyMs)
            }
            // Not our reply — keep waiting (recv timeout will eventually bail us out)
        }
    }

    private static func icmpChecksum(header: inout ICMPHeader) -> UInt16 {
        return withUnsafePointer(to: &header) { ptr in
            ptr.withMemoryRebound(to: UInt16.self, capacity: icmpHeaderSize / 2) { buf in
                var sum: UInt32 = 0
                let count = icmpHeaderSize / 2
                for i in 0..<count {
                    sum += UInt32(buf[i])
                }
                while sum >> 16 != 0 {
                    sum = (sum & 0xFFFF) + (sum >> 16)
                }
                return ~UInt16(sum & 0xFFFF)
            }
        }
    }

    private func notifyChange() {
        guard !results.isEmpty else { return }

        let total = results.count
        var successLatencies: [Double] = []
        var lostCount = 0
        var hasDnsFailure = false

        for r in results {
            switch r.outcome {
            case .success(let ms):
                successLatencies.append(ms)
            case .timeout:
                lostCount += 1
            case .dnsFailure:
                lostCount += 1
                hasDnsFailure = true
            }
        }

        let packetLoss = Double(lostCount) / Double(total) * 100.0
        let avgLatency = successLatencies.isEmpty ? 2000.0 : successLatencies.reduce(0, +) / Double(successLatencies.count)
        let minLatency = successLatencies.min() ?? 0
        let maxLatency = successLatencies.max() ?? 0

        let stats = PingStats(
            packetLossPercent: packetLoss,
            avgMs: avgLatency,
            minMs: minLatency,
            maxMs: maxLatency,
            sampleCount: total,
            dnsFailure: hasDnsFailure
        )
        onChange?(stats)
    }
}
