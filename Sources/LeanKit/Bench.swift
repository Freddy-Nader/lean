import Darwin
import Foundation

/// Launch timing. `LEAN_BENCH=1` prints ms from process start to first window and quits.
enum Bench {
    static func launched() {
        guard ProcessInfo.processInfo.environment["LEAN_BENCH"] == "1" else { return }
        print(String(format: "launch_ms=%.1f", sinceProcessStart() * 1000))
        exit(0)
    }

    static func sinceProcessStart() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1e6
        return Date().timeIntervalSince1970 - started
    }
}
