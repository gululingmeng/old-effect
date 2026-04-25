import UIKit
import AVFoundation
import BNBSdkCore

final class ViewController: UIViewController {

    private let pipeline = BanubaPipeline()
    private let capture = ExternalCameraCapture()

    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let cameraSelector = UISegmentedControl(items: ["External", "Back", "Front"])
    private let agingButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private let questionButtonBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let questionButton = UIButton(type: .system)
    private let questionBubble = QuestionBubbleView()

    private var bubbleHideWorkItem: DispatchWorkItem?
    private var lastQuestion: String?

    private var currentChoice: ExternalCameraCapture.CameraChoice = .back

    private var lastInterfaceOrientation: UIInterfaceOrientation = .unknown

    // Detector watchdog (we keep logs, but we no longer auto-flip orientations here).
    // Orientation is handled at AVCapture layer via `connection.videoOrientation`.
    private var zeroDetectorTicks: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupBanubaView()
        setupUI()
        setupCapture()

        // Default preference: external if available; else back camera.
        if #available(iOS 17.0, *) {
            currentChoice = .external
            cameraSelector.selectedSegmentIndex = ExternalCameraCapture.CameraChoice.external.rawValue
        } else {
            currentChoice = .back
            cameraSelector.selectedSegmentIndex = ExternalCameraCapture.CameraChoice.back.rawValue
        }

        startCamera(choice: currentChoice)

        pipeline.onDetectorTick = { [weak self] detector in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleDetectorTick(detector)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyInterfaceOrientation(force: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onDeviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        bubbleHideWorkItem?.cancel()
    }

    private func setupBanubaView() {
        let v = pipeline.makeOutputView()
        v.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            v.topAnchor.constraint(equalTo: view.topAnchor),
            v.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupUI() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 56)
        ])

        cameraSelector.translatesAutoresizingMaskIntoConstraints = false
        cameraSelector.addTarget(self, action: #selector(onCameraChanged), for: .valueChanged)
        topBar.contentView.addSubview(cameraSelector)

        agingButton.translatesAutoresizingMaskIntoConstraints = false
        agingButton.setTitle(pipeline.isEffectEnabled() ? "Aging: ON" : "Aging: OFF", for: .normal)
        agingButton.tintColor = .white
        agingButton.addTarget(self, action: #selector(onToggleAging), for: .touchUpInside)
        topBar.contentView.addSubview(agingButton)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 3
        view.addSubview(statusLabel)

        setupQuestionUI()

        NSLayoutConstraint.activate([
            cameraSelector.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 12),
            cameraSelector.centerYAnchor.constraint(equalTo: topBar.contentView.centerYAnchor),
            cameraSelector.widthAnchor.constraint(equalToConstant: 260),

            agingButton.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -12),
            agingButton.centerYAnchor.constraint(equalTo: topBar.contentView.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: questionButtonBackground.leadingAnchor, constant: -12)
        ])
    }

    private func setupQuestionUI() {
        questionBubble.alpha = 0
        questionBubble.isHidden = true
        questionBubble.transform = CGAffineTransform(translationX: 0, y: 8)
        questionBubble.accessibilityIdentifier = "questionBubble"
        view.addSubview(questionBubble)

        questionButtonBackground.translatesAutoresizingMaskIntoConstraints = false
        questionButtonBackground.clipsToBounds = true
        questionButtonBackground.layer.cornerRadius = 28
        questionButtonBackground.layer.cornerCurve = .continuous
        questionButtonBackground.layer.borderWidth = 1
        questionButtonBackground.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        questionButtonBackground.layer.shadowColor = UIColor.black.cgColor
        questionButtonBackground.layer.shadowOpacity = 0.18
        questionButtonBackground.layer.shadowRadius = 12
        questionButtonBackground.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.addSubview(questionButtonBackground)

        questionButton.translatesAutoresizingMaskIntoConstraints = false
        questionButton.tintColor = .white
        questionButton.accessibilityIdentifier = "questionButton"
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        questionButton.setImage(UIImage(systemName: "questionmark.circle.fill", withConfiguration: symbolConfig), for: .normal)
        questionButton.addTarget(self, action: #selector(onQuestionTapped), for: .touchUpInside)
        questionButtonBackground.contentView.addSubview(questionButton)

        let bubbleTap = UITapGestureRecognizer(target: self, action: #selector(onBubbleTapped))
        questionBubble.addGestureRecognizer(bubbleTap)

        NSLayoutConstraint.activate([
            questionButtonBackground.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            questionButtonBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            questionButtonBackground.widthAnchor.constraint(equalToConstant: 56),
            questionButtonBackground.heightAnchor.constraint(equalToConstant: 56),

            questionButton.centerXAnchor.constraint(equalTo: questionButtonBackground.contentView.centerXAnchor),
            questionButton.centerYAnchor.constraint(equalTo: questionButtonBackground.contentView.centerYAnchor),

            questionBubble.trailingAnchor.constraint(equalTo: questionButtonBackground.trailingAnchor),
            questionBubble.bottomAnchor.constraint(equalTo: questionButtonBackground.topAnchor, constant: -12),
            questionBubble.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            questionBubble.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.7),
            questionBubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    private func setupCapture() {
        // ✅ 切换相机后，等 session 真正切完再刷新 UI（修复 device 显示不准）
        capture.onConfigurationChanged = { [weak self] in
            self?.updateStatus()
            self?.applyInterfaceOrientation(force: true)
        }

        capture.onSampleBuffer = { [weak self] sb in
            guard let self else { return }

            let vo = self.capture.currentVideoOrientation
            let rotation = self.capture.currentRotationAngle
            let pos = self.capture.activePosition
            let camOri = self.banubaOrientation(for: rotation, position: pos)
            let mirror = (pos == .front)

            // 方向/镜像/position 调试输出
            print("➡️ AVCapture=\(vo)  rot=\(rotation)  Banuba=\(camOri)  pos=\(self.capture.activePosition)  mirror=\(mirror)")

            self.pipeline.push(
                sampleBuffer: sb,
                cameraOrientation: camOri,
                requireMirroring: mirror,
                fieldOfView: self.capture.activeDevice?.activeFormat.videoFieldOfView
            )
        }
    }

    private func banubaOrientation(for rotationAngle: CGFloat,
                                   position: AVCaptureDevice.Position) -> BNBCameraOrientation {
        let normalized = Int(((rotationAngle.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360))

        // Newer devices can expose the front selfie sensor with a 180°-different native mount
        // compared with older hardware. We keep the compensation in one place for easy tuning.
        let compensated: Int
        if position == .front {
            compensated = (normalized + 180) % 360
        } else {
            compensated = normalized
        }

        switch compensated {
        case 90:  return .deg90
        case 180: return .deg180
        case 270: return .deg270
        default:  return .deg0
        }
    }

    @objc private func onDeviceOrientationChanged() {
        applyInterfaceOrientation(force: false)
    }

    private func applyInterfaceOrientation(force: Bool) {
        guard let io = view.window?.windowScene?.interfaceOrientation else { return }
        if !force, io == lastInterfaceOrientation { return }
        lastInterfaceOrientation = io
        capture.setInterfaceOrientation(io)
    }

    private func startCamera(choice: ExternalCameraCapture.CameraChoice) {
        capture.stop()
        capture.start(choice: choice)
    }

    private func handleDetectorTick(_ detector: Int) {
        if detector > 0 {
            zeroDetectorTicks = 0
            return
        }
        zeroDetectorTicks += 1
        if zeroDetectorTicks == 2 {
            print("⚠️ detector still 0 for ~2s. Most likely missing FaceTracker models/resources or license invalid.")
        }
    }

    private func updateStatus() {
        let deviceName = capture.activeDevice?.localizedName ?? "N/A"
        statusLabel.text = "Camera: \(currentChoice)\nDevice: \(deviceName)\nEffect folder: /effects"
    }

    private func showQuestionBubble(text: String) {
        bubbleHideWorkItem?.cancel()
        questionBubble.setText(text)

        let scheduleHide = { [weak self] in
            guard let self else { return }
            let workItem = DispatchWorkItem { [weak self] in
                self?.hideQuestionBubble(animated: true)
            }
            self.bubbleHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: workItem)
        }

        if questionBubble.isHidden {
            questionBubble.isHidden = false
            questionBubble.alpha = 0
            questionBubble.transform = CGAffineTransform(translationX: 0, y: 10).scaledBy(x: 0.98, y: 0.98)
            UIView.animate(withDuration: 0.32,
                           delay: 0,
                           usingSpringWithDamping: 0.84,
                           initialSpringVelocity: 0.22,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                self.questionBubble.alpha = 1
                self.questionBubble.transform = .identity
            }
            scheduleHide()
            return
        }

        UIView.transition(with: questionBubble,
                          duration: 0.24,
                          options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.questionBubble.alpha = 1
            self.questionBubble.transform = .identity
        }
        scheduleHide()
    }

    private func hideQuestionBubble(animated: Bool) {
        bubbleHideWorkItem?.cancel()
        bubbleHideWorkItem = nil

        let animations = {
            self.questionBubble.alpha = 0
            self.questionBubble.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.98, y: 0.98)
        }

        let completion: (Bool) -> Void = { _ in
            self.questionBubble.isHidden = true
        }

        guard animated else {
            animations()
            completion(true)
            return
        }

        UIView.animate(withDuration: 0.22,
                       delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState],
                       animations: animations,
                       completion: completion)
    }

    @objc private func onCameraChanged() {
        guard let choice = ExternalCameraCapture.CameraChoice(rawValue: cameraSelector.selectedSegmentIndex) else {
            return
        }
        currentChoice = choice
        zeroDetectorTicks = 0
        startCamera(choice: choice)
        // UI will be refreshed when the session finishes reconfiguring.
    }

    @objc private func onToggleAging() {
        let enabled = pipeline.toggleEffect()
        agingButton.setTitle(enabled ? "Aging: ON" : "Aging: OFF", for: .normal)
    }

    @objc private func onQuestionTapped() {
        let nextQuestion = QuestionRepository.randomQuestion(excluding: lastQuestion)
        lastQuestion = nextQuestion

        UIView.animate(withDuration: 0.12,
                       animations: {
            self.questionButtonBackground.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                       }, completion: { _ in
            UIView.animate(withDuration: 0.16) {
                self.questionButtonBackground.transform = .identity
            }
        })

        showQuestionBubble(text: nextQuestion)
    }

    @objc private func onBubbleTapped() {
        hideQuestionBubble(animated: true)
    }
}
