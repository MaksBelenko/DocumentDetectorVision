//
//  ViewController.swift
//  VisionCreditScan
//
//  Created by Anupam Chugh on 27/01/20.
//  Copyright © 2020 iowncode. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
    
    var bufferSize: CGSize = .zero
    
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private let videoDataOutput = AVCaptureVideoDataOutput()

    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private var isTapped = false
    
    
    lazy var item : UINavigationItem = {
        let item = UINavigationItem()
        
        item.setRightBarButton(UIBarButtonItem(title: "Scan", style: .plain, target: self, action: #selector(doScan(sender:))), animated: false)
        
        return item
    }()
    
    private var maskLayer = CAShapeLayer()
    
    private var timeOnScan = Date()
    
    
    // MARK: - Selectors
    @objc func doScan(sender: UIButton!){
        self.isTapped = true
    }
    
    
    //MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
//        self.setCameraInput()
        self.showCameraFeed()
//        self.setCameraOutput()
        
        setupAVCapture()
        
        self.navigationController?.navigationBar.setItems([item], animated: false)
    }
    override func viewDidAppear(_ animated: Bool) {

        self.videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        self.captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        
        self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        self.captureSession.stopRunning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.safeAreaLayoutGuide.layoutFrame
    }

    
    
    
    // MARK: - Camera setup
//    private func setCameraInput() {
//        guard let device = AVCaptureDevice.DiscoverySession(
//            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
//            mediaType: .video,
//            position: .back).devices.first else {
//                fatalError("No back camera device found.")
//        }
//        let cameraInput = try! AVCaptureDeviceInput(device: device)
//        self.captureSession.addInput(cameraInput)
//    }
    
    
    
    private func showCameraFeed() {
        self.previewLayer.videoGravity = .resizeAspectFill
        self.view.layer.addSublayer(self.previewLayer)
        self.previewLayer.frame = self.view.frame
    }
    
    
    
//    private func setCameraOutput() {
//        self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
//        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
////        self.videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
//        self.captureSession.addOutput(self.videoDataOutput)
//
//        guard let connection = self.videoDataOutput.connection(with: .video),
//            connection.isVideoOrientationSupported else { return }
//
//        connection.videoOrientation = .portrait
//    }
    
    
    private func setupAVCapture() {
        var deviceInput: AVCaptureDeviceInput!
        
        // Select a video device, make an input
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice!)
        } catch {
            print("Could not create video device input: \(error)")
            return
        }
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd4K3840x2160//.vga640x480 // Model image size is smaller.
        
        // Add a video input
        guard captureSession.canAddInput(deviceInput) else {
            print("Could not add video device input to the session")
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(deviceInput)
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            // Add a video data output
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            print("Could not add video data output to the session")
            captureSession.commitConfiguration()
            return
        }
        
        
        let captureConnection = videoDataOutput.connection(with: .video)
        captureConnection?.videoOrientation = .portrait
        // Always process the frames
        captureConnection?.isEnabled = true
        
        do {
            try  videoDevice!.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            videoDevice!.unlockForConfiguration()
        } catch {
            print(error)
        }
        
        captureSession.commitConfiguration()
    }
    
    
    
    // MARK: - Drawing helpers
    
    private func detectRectangle(in image: CVPixelBuffer) {

//        if Date().timeIntervalSince(timeOnScan) < 0.05 { return }
//        
//        timeOnScan = Date()
        
        let request = VNDetectRectanglesRequest(completionHandler: { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                
                guard let results = request.results as? [VNRectangleObservation] else { return }
                self.removeMask()
                
                guard let rect = results.first else{return}
                    self.drawBoundingBox(rect: rect)
                
                    if self.isTapped{
                        self.isTapped = false
                        self.doPerspectiveCorrection(rect, from: image)
                    }
            }
        })
        
//        request.minimumAspectRatio = VNAspectRatio(1.3)
////        request.minimumAspectRatio = 0.3
//        request.maximumAspectRatio = VNAspectRatio(1.6)
//        request.minimumSize = Float(0.2) // default
//        request.maximumObservations = 1
        
        
        request.maximumObservations = 1 // Vision currently supports up to 16.
        request.minimumConfidence = 0.6 // Be confident.
        request.minimumAspectRatio = 0.2 // height / width
        

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
//        try? imageRequestHandler.perform([request])
        
        // Send the requests to the request handler.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try imageRequestHandler.perform([request])
            } catch let error as NSError {
                print("Failed to perform image request: \(error)")
                return
            }
        }
    }
    

    func doPerspectiveCorrection(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) {
        var ciImage = CIImage(cvImageBuffer: buffer)

        let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
        let topRight = observation.topRight.scaled(to: ciImage.extent.size)
        let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
        let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)

        // pass those to the filter to extract/rectify the image
        ciImage = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight),
        ])

        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let output = UIImage(cgImage: cgImage!)
        //UIImageWriteToSavedPhotosAlbum(output, nil, nil, nil)
        
        let secondVC = TextExtractorVC()
        secondVC.scannedImage = output
        self.navigationController?.pushViewController(secondVC, animated: false)
        
    }
    
    
    
    func drawBoundingBox(rect : VNRectangleObservation) {
    
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewLayer.frame.height)
        let scale = CGAffineTransform.identity.scaledBy(x: self.previewLayer.frame.width, y: self.previewLayer.frame.height)

        let bounds = rect.boundingBox.applying(scale).applying(transform)
        createLayer(in: bounds)

    }

    private func createLayer(in rect: CGRect) {

        let borderWidth: CGFloat = 5.0
        let drawRect = CGRect(x: rect.origin.x - borderWidth,
                              y: rect.origin.y - borderWidth,
                              width: rect.width + 2*borderWidth,
                              height: rect.height + 2*borderWidth)
        
        maskLayer = CAShapeLayer()
        maskLayer.frame = drawRect
        maskLayer.cornerRadius = 10
        maskLayer.opacity = 0.75
        maskLayer.borderColor = UIColor.systemOrange.cgColor
        maskLayer.borderWidth = borderWidth
        
        previewLayer.insertSublayer(maskLayer, at: 1)

    }
    
    func removeMask() {
            maskLayer.removeFromSuperlayer()

    }
}



// MARK: - Delegate method
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            debugPrint("unable to get image from sample buffer")
            return
        }
        
        self.detectRectangle(in: frame)
    }
}



// MARK: - CGPoint extension
extension CGPoint {
   func scaled(to size: CGSize) -> CGPoint {
       return CGPoint(x: self.x * size.width,
                      y: self.y * size.height)
   }
}
