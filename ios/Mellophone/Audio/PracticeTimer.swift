import Combine
import Foundation
import OSLog
import UIKit

/// The practice timer.
///
/// Counts from a WALL CLOCK ANCHOR rather than by incrementing a tick, which is
/// what the web version does with `setInterval`. The difference matters here:
/// practising means the phone gets locked and pocketed, and a suspended app
/// stops receiving ticks. A tick counter would quietly under-count the session
/// by however long the screen was off, which is most of it.
///
/// Storing when it started and subtracting means the answer is right no matter
/// what happened in between.
final class PracticeTimer: ObservableObject {
    @Published private(set) var elapsed: Int = 0
    @Published private(set) var isRunning = false

    /// Seconds banked from previous run segments, so pause and resume add up.
    private var accumulated: TimeInterval = 0
    private var startedAt: Date?
    private var ticker: Timer?

    init() {
        // Recompute the moment the app comes back, rather than waiting for the
        // next tick, so the number on screen is never stale by up to a second at
        // exactly the moment someone is looking at it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        startedAt = Date()
        isRunning = true
        startTicker()
        Log.store.info("[TIMER] started at \(self.accumulated, privacy: .public)s accumulated")
    }

    func pause() {
        guard isRunning else { return }
        accumulated = currentTotal
        startedAt = nil
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        elapsed = Int(accumulated)
        Log.store.info("[TIMER] paused at \(self.elapsed, privacy: .public)s")
    }

    func reset() {
        ticker?.invalidate()
        ticker = nil
        accumulated = 0
        startedAt = nil
        isRunning = false
        elapsed = 0
        Log.store.info("[TIMER] reset")
    }

    private var currentTotal: TimeInterval {
        guard let startedAt else { return accumulated }
        return accumulated + Date().timeIntervalSince(startedAt)
    }

    private func startTicker() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// The ticker only drives the DISPLAY. Missing ticks cannot lose time,
    /// because the value is always recomputed from the anchor.
    @objc private func refresh() {
        guard isRunning else { return }
        let total = Int(currentTotal)
        if total != elapsed { elapsed = total }
    }
}
