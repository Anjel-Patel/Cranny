import AppKit
import AVFoundation
import SwiftUI

/// Front camera preview for the Mirror widget. The camera only runs while the
/// mirror is switched on and the nook is open.
@MainActor
final class CameraService: ObservableObject {
    static let shared = CameraService()

    @Published private(set) var isRunning = false
    @Published private(set) var isDenied = false
    @Published private(set) var noCamera = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.rdbms234.Cranny.camera")
    private var configured = false

    private init() {
        isDenied = [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func toggle() {
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
        let session = SessionBox(session: session)
        queue.async { session.session.stopRunning() }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func run() {
        if !configured {
            guard let device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
            ).devices.first ?? AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device)
            else {
                noCamera = true
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .high
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            configured = true
        }
        noCamera = false
        isRunning = true
        let session = SessionBox(session: session)
        queue.async { session.session.startRunning() }
    }
}

private struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            CATransaction.commit()
        }
    }
}
