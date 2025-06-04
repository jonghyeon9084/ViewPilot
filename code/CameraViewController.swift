import UIKit
import AVFoundation
import Photos

class CameraViewController: UIViewController, PHPhotoLibraryChangeObserver {

    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var lensStackView: UIStackView!
    @IBOutlet weak var topOverlayView: UIView!
    @IBOutlet weak var bottomOverlayView: UIView!
    @IBOutlet weak var galleryButton: UIButton!

    private let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var currentDeviceInput: AVCaptureDeviceInput?
    private var availableDevices: [AVCaptureDevice.DeviceType: AVCaptureDevice] = [:]
    private var deviceTypeMap: [String: AVCaptureDevice.DeviceType] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOverlayViews()
        findAvailableLenses()
        configureCaptureSession()
        configurePreviewLayer()
        captureSession.startRunning()
        setupLensButtons()
        PHPhotoLibrary.shared().register(self) // Register for gallery updates
        setupTapToFocus()
        
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateGalleryThumbnail()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        PHPhotoLibrary.shared().unregisterChangeObserver(self) // Unregister observer
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            self.updateGalleryThumbnail()
        }
    }

    func setupOverlayViews() {
        // Optional: Set overlay colors if needed
        topOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        bottomOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
    }

    func findAvailableLenses() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )

        availableDevices.removeAll()
        deviceTypeMap.removeAll()

        for device in discovery.devices {
            print("\u{1F4F7} 감지된 카메라: \(device.deviceType.rawValue)")

            switch device.deviceType {
            case .builtInUltraWideCamera:
                availableDevices[.builtInUltraWideCamera] = device
                deviceTypeMap["0.5x"] = .builtInUltraWideCamera
            case .builtInWideAngleCamera:
                availableDevices[.builtInWideAngleCamera] = device
                deviceTypeMap["1x"] = .builtInWideAngleCamera
            case .builtInTelephotoCamera:
                availableDevices[.builtInTelephotoCamera] = device
                deviceTypeMap["5x"] = .builtInTelephotoCamera
            default:
                continue
            }
        }
    }

    func configureCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        if let wideDevice = availableDevices[.builtInWideAngleCamera],
           let input = try? AVCaptureDeviceInput(device: wideDevice),
           captureSession.canAddInput(input) {
            captureSession.addInput(input)
            currentDeviceInput = input
        } else {
            print("❌ 기본 카메라 입력 추가 실패")
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
    }

    func configurePreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = previewView.bounds
        previewView.layer.insertSublayer(previewLayer, at: 0)
        previewView.bringSubviewToFront(bottomOverlayView)

        if let connection = previewLayer.connection {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .landscapeRight
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds

            let fullWidth = previewView.bounds.width
            let fullHeight = previewView.bounds.height
            
            // 3:4 기준 영역 높이 계산
            let cropHeight = fullWidth * 4 / 3
        
        // 아래 여백을 더 길게 (예: 60pt 더 줌)
            let totalVerticalPadding = fullHeight - cropHeight
            let bottomPadding = totalVerticalPadding * 0.6
            let topPadding = totalVerticalPadding - bottomPadding

            // 오버레이 위치 설정
        topOverlayView.frame = CGRect(x: 0, y: 0, width: fullWidth, height: topPadding)
            bottomOverlayView.frame = CGRect(x: 0, y: fullHeight - bottomPadding, width: fullWidth, height: bottomPadding)
    }

    @IBAction func captureButtonTapped(_ sender: UIButton) {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc func lensButtonTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal),
              let type = deviceTypeMap[title],
              let device = availableDevices[type] else {
            print("❌ 렌즈 전환 실패: \(sender.title(for: .normal) ?? "-")")
            return
        }

        if currentDeviceInput?.device.uniqueID == device.uniqueID {
            print("⚠️ 이미 선택된 렌즈입니다")
            return
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            captureSession.beginConfiguration()
            if let currentInput = currentDeviceInput {
                captureSession.removeInput(currentInput)
            }

            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                currentDeviceInput = newInput
                print("✅ \(title) 렌즈 전환 완료")
            } else {
                print("❌ canAddInput 실패")
            }
            captureSession.commitConfiguration()

        } catch {
            print("❌ 렌즈 전환 실패: \(error)")
        }
    }

    func setupLensButtons() {
        let labels = ["0.5x", "1x", "5x"]
        for label in labels {
            guard let type = deviceTypeMap[label],
                  availableDevices[type] != nil else {
                print("⚠️ \(label) 렌즈 없음, 버튼 스킵")
                continue
            }

            let button = UIButton(type: .system)
            button.setTitle(label, for: .normal)
            button.setTitleColor(.white, for: .normal)

            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.4)
            config.cornerStyle = .capsule
            button.configuration = config

            button.addTarget(self, action: #selector(lensButtonTapped(_:)), for: .touchUpInside)
            lensStackView.addArrangedSubview(button)
        }

        topOverlayView.isUserInteractionEnabled = false
        bottomOverlayView.isUserInteractionEnabled = false
    }

    func updateGalleryThumbnail() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        if let asset = fetchResult.firstObject {
            let imageManager = PHImageManager.default()
            let size = CGSize(width: 60 * UIScreen.main.scale, height: 60 * UIScreen.main.scale)

            imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: nil) { image, _ in
                DispatchQueue.main.async {
                    self.galleryButton.setImage(image, for: .normal)
                    self.galleryButton.imageView?.contentMode = .scaleAspectFill
                    self.galleryButton.clipsToBounds = true
                    self.galleryButton.layer.cornerRadius = 8
                }
            }
        }
    }

    @IBAction func galleryButtonTapped(_ sender: UIButton) {
        print("🖼️ 갤러리 버튼 탭됨")
        
        let customGalleryVC = CustomGalleryViewController()
        customGalleryVC.modalPresentationStyle = .fullScreen
        present(customGalleryVC, animated: true)
    }

    func setupTapToFocus() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
        previewView.addGestureRecognizer(tapGesture)
    }

    @objc func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: previewView)
        let focusPoint = CGPoint(x: location.y / previewView.bounds.height, y: 1.0 - (location.x / previewView.bounds.width))

        guard let device = currentDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            print("❌ 초점 설정 실패: \(error)")
        }

        showFocusIndicator(at: location)
    }

    func showFocusIndicator(at point: CGPoint) {
        let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        focusView.center = point
        focusView.layer.borderColor = UIColor.yellow.cgColor
        focusView.layer.borderWidth = 2
        focusView.layer.cornerRadius = 40
        focusView.backgroundColor = UIColor.clear
        previewView.addSubview(focusView)

        UIView.animate(withDuration: 0.3, animations: {
            focusView.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        }) { _ in
            UIView.animate(withDuration: 0.3, animations: {
                focusView.alpha = 0
            }) { _ in
                focusView.removeFromSuperview()
            }
        }
    }
}

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("❌ 이미지 처리 실패")
            return
        }

        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                DispatchQueue.main.async {
                    self.updateGalleryThumbnail()
                }
                print("✅ 사진 저장 완료")
            } else {
                print("❌ 사진 저장 권한 없음")
            }
        }
    }
}

extension CGFloat {
    var clean: String {
        return truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", self)
            : String(format: "%.1f", self)
    }
}
