

import UIKit
import AVFoundation
import BNBSdkApi
import BNBSdkCore
import BNBEffectPlayer
import CoreImage
/// Banuba PlayerAPI pipeline that accepts frames from any AVCaptureSession (built-in or external camera)
/// and renders the processed output to an EffectPlayerView.
final class BanubaPipeline {

    /// Name of the local effect folder under app bundle path "effects/<EffectName>".
    /// If you don't have an effect, keep it empty and the pipeline will just render the camera feed.
    private let agingEffectName = "effect-4.15" // sample "old" effect from Banuba quickstarts
    /// A debug effect that is known to include face recognition/landmarks in Banuba samples.
    private let debugTrackingEffectName = "DebugWireframe"

    // ✅ Avoid name collision with Foundation.Stream by aliasing Banuba Stream type.
    private typealias BNBStream = BNBSdkApi.Stream

    private let player: Player
    private let stream: BNBStream
    private let outputView: EffectPlayerView
    private let ciContext = CIContext()
    private var loggedFmt = false
    private var isEffectOn: Bool = false

    /// Exposes detector count once per second (same cadence as debug prints).
    /// Useful for UI-side auto-calibration (orientation / mirroring) without attaching another listener.
    var onDetectorTick: ((Int) -> Void)?

    private final class DebugFrameListener: NSObject, BNBFrameDataListener {

        private var lastLogTs: CFTimeInterval = CACurrentMediaTime()
        private var frames = 0

        var onTick: ((Int) -> Void)?

        func onFrameDataProcessed(_ frameData: BNBFrameData?) {
            frames += 1
            let now = CACurrentMediaTime()
            guard now - lastLogTs >= 1.0 else { return }
            lastLogTs = now

            guard let fD = frameData else {
                print("🟨 frameData=nil  fps=\(frames)")
                frames = 0
                return
            }

            // ① 最重要：Face Detector 是否能检测到脸（不依赖 FRX）
            let detectorCount = fD.getFaceDetectorResult().count

            // ② FRX（可能为 nil：取决于效果/功能是否产出该结果）
            let frx = fD.getFrxRecognitionResult()
            let frxFaces = frx?.getFaces() ?? []
            let frxCount = frxFaces.count

            // ③ Landmarks：从 BNBFaceData 取
            let lmNums = frxFaces.first?.getLandmarks() ?? []
            let lmPoints = lmNums.count / 2  // x,y 成对

            print("🙂 detector=\(detectorCount)  frxFaces=\(frxCount)  landmarks=\(lmPoints)  fps=\(frames)")

            onTick?(detectorCount)
            frames = 0
        }
    }

    private let debugListener = DebugFrameListener()
    
    private final class FaceNumberListenerImpl: NSObject, BNBFaceNumberListener {
        func onFaceNumberChanged(_ faceNumber: Int32) {
            print("👤 faceNumberListener=\(faceNumber)")
        }
    }
    private let faceNumberListener = FaceNumberListenerImpl()

    init() {
        self.player = Player()
        self.stream = BNBStream()                      // ✅ initialize exactly once
        self.outputView = EffectPlayerView(frame: .zero)

        // Connect input + output.
        player.use(input: stream, outputs: [outputView])

        // Start the render loop.
        player.play()
        debugListener.onTick = { [weak self] detector in
            self?.onDetectorTick?(detector)
        }
        player.effectPlayer.add(debugListener)
        
        player.effectPlayer.add(faceNumberListener)

        // Print effect folder status for debugging.
        debugPrintEffectBundleStatus(debugTrackingEffectName)
        debugPrintEffectBundleStatus(agingEffectName)

        // IMPORTANT:
        // Many Banuba results (FRX / landmarks, and sometimes even detector output) are produced
        // only when an effect that enables face recognition is active.
        // To avoid `detector=0` forever, try to load a tracking-capable effect at startup.
        let initialEffect = bundledEffectPath(agingEffectName)
            ?? bundledEffectPath(debugTrackingEffectName)
            ?? ""
        isEffectOn = (initialEffect != "")
        if initialEffect.isEmpty {
            _ = player.load(effect: "", sync: true)
            print("⚠️ No bundled effects found under /effects. Face tracking may stay disabled.")
        } else {
            print("🎬 initial effect:", initialEffect)
            _ = player.load(effect: initialEffect, sync: true)
        }
    }

    func makeOutputView() -> EffectPlayerView {
        outputView
    }

    func isEffectEnabled() -> Bool {
        isEffectOn
    }
    
    private func debugPrintEffectBundleStatus(_ name: String) {
        let fm = FileManager.default
        if let url = Bundle.main.resourceURL?.appendingPathComponent("effects/\(name)") {
            print("🔎 effects path:", url.path, "exists:", fm.fileExists(atPath: url.path))
            if let items = try? fm.contentsOfDirectory(atPath: url.path) {
                print("📦 effects/\(name) items:", items.prefix(20))
            }
        }
    }

    private func bundledEffectPath(_ name: String) -> String? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("effects/\(name)") else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    private func toBGRA(_ pb: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: w,
            kCVPixelBufferHeightKey: h,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard let out else { return nil }

        ciContext.render(CIImage(cvPixelBuffer: pb), to: out)
        return out
    }

    func setEffectEnabled(_ enabled: Bool) {
        isEffectOn = enabled

        let effectPath = enabled ? (bundledEffectPath(agingEffectName) ?? agingEffectName) : ""
        print("🎬 loading effect:", effectPath)

        let immediate = player.load(effect: effectPath, sync: false) { effect in
            if let effect {
                print("✅ effect active:", effect)
            } else {
                print("❌ effect activation failed for:", effectPath)
            }
        }

        if enabled && immediate == nil {
            print("❌ load(effect:) returned nil immediately:", effectPath)
        }
    }

    @discardableResult
    func toggleEffect() -> Bool {
        setEffectEnabled(!isEffectOn)
        return isEffectOn
    }

    /// Push a camera frame into Banuba pipeline.
    /// - Parameters:
    ///   - sampleBuffer: camera frame.
    ///   - cameraOrientation: orientation enum used by Banuba.
    ///   - requireMirroring: for selfie-style mirroring.
    ///   - fieldOfView: camera FOV in degrees. Pass nil if unknown.
    func push(sampleBuffer: CMSampleBuffer,
              cameraOrientation: BNBCameraOrientation,
              requireMirroring: Bool,
              fieldOfView: Float?) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if !loggedFmt {
            loggedFmt = true
            print("🎥 input fmt=\(fmt) size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
        }

        let pbForBNB: CVPixelBuffer = {
            if fmt == kCVPixelFormatType_32BGRA { return pixelBuffer }
            return toBGRA(pixelBuffer) ?? pixelBuffer
        }()
        // ✅ Banuba expects non-optional Float; use default 60 if unknown/invalid.
        let fov: Float = {
            let v = fieldOfView ?? 60
            return (v > 1) ? v : 60
        }()

        // ✅ create(...) returns optional frame data
        guard let frameData = BNBFrameData.create(
            cvBuffer: pbForBNB,
            faceOrientation: 0,
            cameraOrientation: cameraOrientation,
            requireMirroring: requireMirroring,
            fieldOfView: fov
        ) else {
            return
        }

        // ✅ Push to Banuba input stream
        stream.push(frameData: frameData)
    }

    deinit {
        player.effectPlayer.remove(debugListener)
        player.effectPlayer.remove(faceNumberListener)
        player.stop()
    }
}
