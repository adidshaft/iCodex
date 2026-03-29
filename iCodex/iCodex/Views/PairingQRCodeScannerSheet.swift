import SwiftUI
import AVFoundation

struct PairingQRCodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onScannedCode: (String) -> Void
    let onScannerError: (String) -> Void

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRCodeScannerRepresentable(
                    onCodeScanned: { code in
                        onScannedCode(code)
                        dismiss()
                    },
                    onScannerError: { message in
                        errorMessage = message
                        onScannerError(message)
                    }
                )
                .ignoresSafeArea()

                VStack(spacing: 8) {
                    Text("Scan the pairing QR from iCodex-Connect on your Mac")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                    } else {
                        Text("This QR fills in the Mac IP, port, and passcode automatically.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.62))
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    let onScannerError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onScannerError: onScannerError)
    }

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let controller = QRCodeScannerViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {
        uiViewController.coordinator = context.coordinator
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCodeScanned: (String) -> Void
        private let onScannerError: (String) -> Void
        private var hasScannedCode = false

        init(onCodeScanned: @escaping (String) -> Void, onScannerError: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onScannerError = onScannerError
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScannedCode else { return }
            guard
                let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                object.type == .qr,
                let value = object.stringValue,
                !value.isEmpty
            else {
                return
            }

            hasScannedCode = true
            onCodeScanned(value)
        }

        func reportError(_ message: String) {
            onScannerError(message)
        }
    }
}

private final class QRCodeScannerViewController: UIViewController {
    var coordinator: QRCodeScannerRepresentable.Coordinator?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let overlayLabel = UILabel()
    private var didConfigureSession = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        overlayLabel.textAlignment = .center
        overlayLabel.textColor = .white
        overlayLabel.font = .preferredFont(forTextStyle: .body)
        overlayLabel.numberOfLines = 0
        overlayLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        overlayLabel.layer.cornerRadius = 12
        overlayLabel.layer.masksToBounds = true
        overlayLabel.isHidden = true
        overlayLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayLabel)

        NSLayoutConstraint.activate([
            overlayLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            overlayLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            overlayLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            overlayLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])

        configureScanner()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func configureScanner() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.setupCaptureSessionIfNeeded()
                    } else {
                        self.showOverlayMessage("Camera access is required to scan the pairing QR code.")
                    }
                }
            }
        default:
            showOverlayMessage("Enable Camera access in Settings to scan the pairing QR code.")
        }
    }

    private func setupCaptureSessionIfNeeded() {
        guard !didConfigureSession else {
            startSession()
            return
        }
        didConfigureSession = true

        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            showOverlayMessage("This device does not have a camera available for QR scanning.")
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            guard captureSession.canAddInput(videoInput) else {
                showOverlayMessage("Unable to start the camera for QR scanning.")
                return
            }
            captureSession.addInput(videoInput)

            let metadataOutput = AVCaptureMetadataOutput()
            guard captureSession.canAddOutput(metadataOutput) else {
                showOverlayMessage("Unable to read QR codes from the camera feed.")
                return
            }
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(coordinator, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]

            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.insertSublayer(previewLayer, at: 0)
            self.previewLayer = previewLayer

            startSession()
        } catch {
            showOverlayMessage("Unable to access the camera for QR scanning.")
        }
    }

    private func startSession() {
        overlayLabel.isHidden = true
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
        }
    }

    private func showOverlayMessage(_ message: String) {
        overlayLabel.text = "  \(message)  "
        overlayLabel.isHidden = false
        coordinator?.reportError(message)
    }
}
