//
//  MotionMonitor.swift
//  CameraApp
//
//  Wraps Core Motion so the analysis pipeline can ask "how still is the phone
//  right now?" without blocking on sensor callbacks.
//
//  Updates land on a private operation queue and are smoothed into a pair of
//  scalars behind a lock; readers only ever see the latest smoothed values.
//

import CoreMotion
import Foundation

final class MotionMonitor: @unchecked Sendable {

    /// Exponential smoothing factor. Low enough to ride out sensor noise,
    /// high enough that letting go of a shake is felt within ~100 ms.
    private let smoothing = 0.3
    private let updateInterval = 1.0 / 30.0

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.cameraapp.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private let lock = NSLock()
    private var rotationRate: Double = 0
    private var userAcceleration: Double = 0
    private var gravityX: Double = 0
    private var gravityY: Double = 0
    private var hasReading = false
    private var isRunning = false

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        lock.lock()
        let alreadyRunning = isRunning
        if !alreadyRunning { isRunning = true }
        lock.unlock()
        guard !alreadyRunning, manager.isDeviceMotionAvailable else { return }

        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.ingest(motion)
        }
    }

    func stop() {
        lock.lock()
        isRunning = false
        rotationRate = 0
        userAcceleration = 0
        gravityX = 0
        gravityY = 0
        hasReading = false
        lock.unlock()
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }

    /// The latest smoothed reading, or `nil` when Core Motion has not produced
    /// one (Simulator, or motion updates disabled).
    func currentReading() -> MotionReading? {
        lock.lock()
        defer { lock.unlock() }
        guard hasReading else { return nil }
        return MotionReading(
            rotationRate: rotationRate,
            userAcceleration: userAcceleration,
            gravityX: gravityX,
            gravityY: gravityY
        )
    }

    private func ingest(_ motion: CMDeviceMotion) {
        let rate = magnitude(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
        let acceleration = magnitude(
            motion.userAcceleration.x,
            motion.userAcceleration.y,
            motion.userAcceleration.z
        )

        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        if hasReading {
            rotationRate += (rate - rotationRate) * smoothing
            userAcceleration += (acceleration - userAcceleration) * smoothing
            gravityX += (motion.gravity.x - gravityX) * smoothing
            gravityY += (motion.gravity.y - gravityY) * smoothing
        } else {
            rotationRate = rate
            userAcceleration = acceleration
            gravityX = motion.gravity.x
            gravityY = motion.gravity.y
            hasReading = true
        }
    }

    private func magnitude(_ x: Double, _ y: Double, _ z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }
}
