//
//  ViewController.swift
//  CitizenSkyView
//
//  Created by Jeremy on 5/15/17.
//  Copyright © 2017 CET. All rights reserved.
//

import UIKit
import AWSCore
import AWSCognito
import AWSS3
import AVFoundation

class ViewController: UIViewController {
    
    
    //MARK: Properties
    let captureSession = AVCaptureSession()
    var capturePhotoOutput = AVCapturePhotoOutput()
    var isCaptureSessionConfigured = false


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: Actions
    @IBAction func takePicture(_ sender: UIButton){
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                                identityPoolId:"us-west-2:43473766-619f-4209-996b-7dc61e65ccf1")
        let configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        

        let cameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back)

        
        var possibleCameraInput : AVCaptureInput?
        do {
            possibleCameraInput = try AVCaptureDeviceInput(device:cameraDevice)
        } catch {
            print("Error setting up capture device input")
        }
        
        if let backCameraInput = possibleCameraInput as? AVCaptureDeviceInput {
            if self.captureSession.canAddInput(backCameraInput) {
                self.captureSession.addInput(backCameraInput)
            }
        }
        
        let authorizationStatus = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        switch authorizationStatus {
        case .notDetermined:
            // permission dialog not yet presented, request authorization
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo,
                                                      completionHandler: { (granted:Bool) -> Void in
                                                        if granted {
                                                            // go ahead
                                                        }
                                                        else {
                                                            // user denied, nothing much to do
                                                            print("User denied camera access")
                                                            return
                                                        }
            })
        case .authorized:
            // go ahead
            
            break
        case .denied, .restricted:
            print("Denied or restricted access")
            return
            // the user explicitly denied camera usage or is not allowed to access the camera devices
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        previewLayer?.frame = view.bounds
        view.layer.addSublayer(previewLayer!)
        

        if self.captureSession.canAddOutput(self.capturePhotoOutput) {
            self.captureSession.addOutput(self.capturePhotoOutput)
        }
        

            
        let connection = self.capturePhotoOutput.connection(withMediaType: AVMediaTypeVideo)
        
        // update the video orientation to the device one
        connection?.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.current.orientation.rawValue)!
        
        self.capturePhotoOutput.captureStillImageAsynchronouslyFromConnection(connection) {
            (imageDataSampleBuffer, error) -> Void in
            
            if error == nil {
                
                // if the session preset .Photo is used, or if explicitly set in the device's outputSettings
                // we get the data already compressed as JPEG
                
                let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                
                // the sample buffer also contains the metadata, in case we want to modify it
                let metadata:NSDictionary = CMCopyDictionaryOfAttachments(nil, imageDataSampleBuffer, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate)).takeUnretainedValue()
                
                if let image = UIImage(data: imageData) {
                    // save the image or do something interesting with it
                    ...
                }
            }
            else {
                NSLog("error while capturing still image: \(error)")
            }
        }

        
        
        
        let transferManager = AWSS3TransferManager.default()
        let uploadRequest = AWSS3TransferManagerUploadRequest()
        uploadRequest?.bucket = "cu-sky-imager"
        uploadRequest?.key = "test-ios-image"
        //uploadRequest.body = uploadingfileurl
        //uploadRequest.contentLength = fileSize
        
        transferManager.upload(uploadRequest!).continueWith(executor: AWSExecutor.mainThread(), block: { (task:AWSTask<AnyObject>) -> Any? in
            print("Uploaded")
        })
        
    }
    
    
    
    func checkCameraAuthorization(_ completionHandler: @escaping ((_ authorized: Bool) -> Void)) {
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized:
            //The user has previously granted access to the camera.
            completionHandler(true)
            
        case .notDetermined:
            // The user has not yet been presented with the option to grant video access so request access.
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { success in
                completionHandler(success)
            })
            
        case .denied:
            // The user has previously denied access.
            completionHandler(false)
            
        case .restricted:
            // The user doesn't have the authority to request access e.g. parental restriction.
            completionHandler(false)
        }
    }
    
    
    
    
    func defaultDevice() -> AVCaptureDevice {
        if let device = AVCaptureDevice.defaultDevice(withDeviceType: .builtInDualCamera,
                                                      mediaType: AVMediaTypeVideo,
                                                      position: .back) {
            return device // use dual camera on supported devices
        } else if let device = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera,
                                                             mediaType: AVMediaTypeVideo,
                                                             position: .back) {
            return device // use default back facing camera otherwise
        } else {
            fatalError("All supported devices are expected to have at least one of the queried capture devices.")
        }
    }
    
    
    
    
    func configureCaptureSession(_ completionHandler: ((_ success: Bool) -> Void)) {
        var success = false
        defer { completionHandler(success) } // Ensure all exit paths call completion handler.
        
        // Get video input for the default camera.
        let videoCaptureDevice = defaultDevice()
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            print("Unable to obtain video input for default camera.")
            return
        }
        
        // Create and configure the photo output.
        let capturePhotoOutput = AVCapturePhotoOutput()
        capturePhotoOutput.isHighResolutionCaptureEnabled = true
        capturePhotoOutput.isLivePhotoCaptureEnabled = capturePhotoOutput.isLivePhotoCaptureSupported
        
        // Make sure inputs and output can be added to session.
        guard self.captureSession.canAddInput(videoInput) else { return }
        guard self.captureSession.canAddOutput(capturePhotoOutput) else { return }
        
        // Configure the session.
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = AVCaptureSessionPresetPhoto
        self.captureSession.addInput(videoInput)
        self.captureSession.addOutput(capturePhotoOutput)
        self.captureSession.commitConfiguration()
        
        self.capturePhotoOutput = capturePhotoOutput
        
        success = true
    }


}

