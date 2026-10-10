import AppKit
import AVFoundation
import SwiftUI

/// Front camera preview for the Mirror. The camera only runs while the mirror is
/// switched on and the nook is open.
///
/// A capture session can't be changed from two threads at once, so everything that
/// touches it (setup, start, stop) happens on one serial queue, and a single preview
/// layer is attached once and reused. Clicks only change whether the camera should
/// run; the queue then catches up with the latest wish, however fast the clicks come.
@MainActor
final class CameraService: ObservableObject {
    static let shared = CameraService()

    @Published private(set) var isRunning = false
    @Published private(set) var isDenied = false
    @Published private(set) var noCamera = false

    /// The one preview of the camera, shown by whichever mirror is on screen.
    var previewLayer: AVCaptureVideoPreviewLayer { engine.previewLayer }

    private let engine = CameraEngine()
    private var lastToggle = Date.distantPast

    private init() {
        isDenied = [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func toggle() {
        // Clicks closer together than this are a double click, not two wishes.
        guard Date().timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = Date()
        isRunning ? stop() : start()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isDenied = false
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let camera = CameraService.shared
                        camera.isDenied = !granted
                        if granted { camera.run() }
                    }
                }
            }
        default:
            isDenied = true
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.setRunning(false)
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func run() {
        guard !isRunning else { return }
        noCamera = false
        isRunning = true
        engine.setRunning(true) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let camera = CameraService.shared
                    camera.noCamera = true
                    camera.isRunning = false
                }
            }
        }
    }
}

/// Owns the capture session. Everything that touches it runs on `queue`.
private final class CameraEngine: @unchecked Sendable {
    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "io.github.rdbms234.Cranny.camera")
    private let lock = NSLock()
    private var wantsRunning = false
    /// Only read and written on `queue`.
    private var configured = false

    init() {
        // Attached before the session is ever configured or started, and never again.
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    /// Records whether the camera should run, then brings the session in line on the queue.
    /// `onNoCamera` is called if there's no camera to start.
    func setRunning(_ running: Bool, onNoCamera: @escaping @Sendable () -> Void = {}) {
        lock.withLock { wantsRunning = running }
        queue.async { self.apply(onNoCamera: onNoCamera) }
    }

    private func apply(onNoCamera: @Sendable () -> Void) {
        let running = lock.withLock { wantsRunning }
        if running {
            guard configureIfNeeded() else {
                lock.withLock { wantsRunning = false }
                onNoCamera()
                return
            }
            if !session.isRunning {
                session.startRunning()
                Log.app.info("Camera started")
            }
        } else if session.isRunning {
            session.stopRunning()
            Log.app.info("Camera stopped")
        }
    }

    private func configureIfNeeded() -> Bool {
        if configured { return true }
        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
        ).devices.first ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else { return false }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        // The preview's connection exists once the input is added. Mirror it like a mirror.
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            session.beginConfiguration()
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            session.commitConfiguration()
        }
        configured = true
        return true
    }
}

/// Shows the shared camera preview. Only one view can hold it at a time; the one that
/// appeared last takes it.
struct CameraPreview: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context: Context) -> Host { Host(preview: layer) }

    func updateNSView(_ view: Host, context: Context) { view.attach() }

    final class Host: NSView {
        let preview: CALayer

        init(preview: CALayer) {
            self.preview = preview
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            attach()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func attach() {
            guard let layer, preview.superlayer !== layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.addSublayer(preview)
            preview.frame = bounds
            CATransaction.commit()
        }

        override func layout() {
            super.layout()
            guard preview.superlayer === layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.frame = bounds
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                attach()
            } else if preview.superlayer === layer {
                preview.removeFromSuperlayer()
            }
        }
    }
}
