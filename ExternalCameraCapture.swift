
import AVFoundation
import UIKit

final class ExternalCameraCapture: NSObject {

    enum CameraChoice: Int, CaseIterable {
        case external = 0
        case back = 1
        case front = 2
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "capture.session.queue")
    private let videoOutputQueue = DispatchQueue(label: "capture.video.output.queue")
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private var videoConnection: AVCaptureConnection?
    private(set) var isMirrored: Bool = false
    private(set) var activeDevice: AVCaptureDevice?
    private(set) var activePosition: AVCaptureDevice.Position = .unspecified
    var onConfigured: (() -> Void)?

    var onConfigurationChanged: (() -> Void)?

    /// Desired orientation for the next (re)configuration. Kept in sync with interface orientation.
    var preferredVideoOrientation: AVCaptureVideoOrientation = .portrait
    private(set) var currentVideoOrientation: AVCaptureVideoOrientation = .portrait
    /// Rotation angle (0..360). On iPadOS 17+ this can be fed by `AVCaptureDevice.RotationCoordinator`
    /// which is required for reliable orientation with external cameras.
    private(set) var currentRotationAngle: CGFloat = 90
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    @available(iOS 17.0, *)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @available(iOS 17.0, *)
    private var rotationObserver: NSKeyValueObservation?

    /// Keep AVCapture output orientation aligned with the current interface orientation.
    /// Do not apply front-camera-specific left/right swapping here.
    /// Some devices need different selfie sensor compensation, and forcing a swap can
    /// make the front camera appear rotated by 180° on newer hardware.
    private static func adjustedOrientationForConnection(_ vo: AVCaptureVideoOrientation,
                                                         position: AVCaptureDevice.Position) -> AVCaptureVideoOrientation {
        vo
    }
    
    
    func start(choice: CameraChoice) {
        sessionQueue.async {
            self.configureSession(choice: choice)
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            if #available(iOS 17.0, *) {
                self.rotationObserver = nil
                self.rotationCoordinator = nil
            }
        }
    }

    private func configureSession(choice: CameraChoice) {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Clear existing inputs/outputs
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        guard let device = selectDevice(choice: choice) else {
            session.commitConfiguration()
            return
        }
        activeDevice = device
        activePosition = device.position
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            return
        }

        // Force BGRA output to keep frame pipeline simple (Banuba Stream/BNBFrameData accepts CVPixelBuffer).
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        videoConnection = videoOutput.connection(with: .video)

        if let conn = videoConnection {
            // 1) Keep capture output aligned with UI orientation.
            // On iOS 17+, prefer `videoRotationAngle` (Apple’s recommended way, esp. for external cameras).
            if #available(iOS 17.0, *) {
                let appliedVO = Self.adjustedOrientationForConnection(preferredVideoOrientation, position: device.position)
                let angle = Self.rotationAngle(from: appliedVO)
                if conn.isVideoRotationAngleSupported(angle) {
                    conn.videoRotationAngle = angle
                    currentRotationAngle = angle
                } else if conn.isVideoOrientationSupported {
                    conn.videoOrientation = appliedVO
                }
            } else if conn.isVideoOrientationSupported {
                let appliedVO = Self.adjustedOrientationForConnection(preferredVideoOrientation, position: device.position)
                conn.videoOrientation = appliedVO
            }

            currentVideoOrientation = conn.videoOrientation
            if #available(iOS 17.0, *) {
                currentRotationAngle = conn.videoRotationAngle
            } else {
                currentRotationAngle = Self.rotationAngle(from: currentVideoOrientation)
            }

            // 2) 采集层不做镜像（镜像统一交给 Banuba 的 requireMirroring 控制）
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = false
            }
            isMirrored = conn.isVideoMirrored
        }

        // iPadOS 17+ external camera rotation: rely on RotationCoordinator (Apple recommended).
        // For built-in cameras we keep a simpler (and more predictable) path.
        if #available(iOS 17.0, *), device.deviceType == .external {
            rotationObserver = nil
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            rotationObserver = rotationCoordinator?.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                guard let self else { return }
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                self.currentRotationAngle = angle
                self.currentVideoOrientation = Self.videoOrientation(fromRotationAngle: angle)
            }
        }

        session.commitConfiguration()
        DispatchQueue.main.async { [weak self] in
            self?.onConfigured?()
            self?.onConfigurationChanged?()
        }
    }

    /// Call this whenever UI orientation changes (e.g. rotation).
    /// Updates the connection orientation so the sampleBuffer metadata stays consistent.
    func setInterfaceOrientation(_ io: UIInterfaceOrientation) {
        let vo: AVCaptureVideoOrientation
        switch io {
        case .portrait: vo = .portrait
        case .portraitUpsideDown: vo = .portraitUpsideDown
        case .landscapeLeft: vo = .landscapeLeft
        case .landscapeRight: vo = .landscapeRight
        default: vo = .portrait
        }

        preferredVideoOrientation = vo
        let appliedVO = Self.adjustedOrientationForConnection(vo, position: activePosition)
        currentRotationAngle = Self.rotationAngle(from: appliedVO)

        sessionQueue.async { [weak self] in
            guard let self, let conn = self.videoConnection else { return }
            if #available(iOS 17.0, *) {
                let angle = Self.rotationAngle(from: appliedVO)
                if conn.isVideoRotationAngleSupported(angle) {
                    conn.videoRotationAngle = angle
                    self.currentRotationAngle = angle
                } else if conn.isVideoOrientationSupported {
                    conn.videoOrientation = appliedVO
                }
            } else if conn.isVideoOrientationSupported {
                conn.videoOrientation = appliedVO
            }

            self.currentVideoOrientation = conn.videoOrientation
        }
    }

    private static func rotationAngle(from vo: AVCaptureVideoOrientation) -> CGFloat {
        switch vo {
        case .portrait: return 90
        case .landscapeRight: return 0
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        @unknown default: return 90
        }
    }

    private static func videoOrientation(fromRotationAngle angle: CGFloat) -> AVCaptureVideoOrientation {
        let snapped = (Int((angle / 90).rounded()) * 90) % 360
        switch snapped {
        case 0: return .landscapeRight
        case 90: return .portrait
        case 180: return .landscapeLeft
        case 270: return .portraitUpsideDown
        default: return .portrait
        }
    }

    private func selectDevice(choice: CameraChoice) -> AVCaptureDevice? {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(iOS 17.0, *) {
            deviceTypes.append(.external)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        let devices = discovery.devices

        switch choice {
        case .external:
            if #available(iOS 17.0, *) {
                return devices.first(where: { $0.deviceType == .external })
            }
            return nil
        case .back:
            return devices.first(where: { $0.position == .back && $0.deviceType == .builtInWideAngleCamera })
        case .front:
            return devices.first(where: { $0.position == .front && $0.deviceType == .builtInWideAngleCamera })
        }
    }
}

extension ExternalCameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        currentVideoOrientation = connection.videoOrientation
        if #available(iOS 17.0, *) {
            currentRotationAngle = connection.videoRotationAngle
        } else {
            currentRotationAngle = Self.rotationAngle(from: currentVideoOrientation)
        }
        isMirrored = connection.isVideoMirrored
        onSampleBuffer?(sampleBuffer)
    }
}
