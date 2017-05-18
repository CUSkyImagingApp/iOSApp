//
//  ImageCaptureViewController.swift
//  CitizenSkyView
//
//  Created by Jeremy on 5/17/17.
//  Copyright © 2017 CET. All rights reserved.
//

import UIKit
import AWSCore
import AWSCognito
import AWSS3
import AVFoundation
import TrueTime


class ImageCaptureViewController: UIViewController, AVCapturePhotoCaptureDelegate  {
    
    
    //MARK: Properties
    //MARK: Properties
    var captureSesssion : AVCaptureSession!
    var cameraOutput : AVCapturePhotoOutput!
    var previewLayer : AVCaptureVideoPreviewLayer!
    
    var credentialProvider : AWSCognitoCredentialsProvider!
    var configuration : AWSServiceConfiguration!
    var transferManager : AWSS3TransferManager!
    
    var trueTimeClient : TrueTimeClient?
    var timer = Timer()
    
    var onThirtySecondTimer = false
    
    @IBOutlet weak var capturedImage: UIImageView!
    @IBOutlet weak var previewView: UIView!


    override func viewDidLoad() {
        super.viewDidLoad()
        credentialProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                           identityPoolId:"us-west-2:43473766-619f-4209-996b-7dc61e65ccf1")
        configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        transferManager = AWSS3TransferManager.default()
        
        trueTimeClient = TrueTimeClient.sharedInstance
        
        
        captureSesssion = AVCaptureSession()
        captureSesssion.sessionPreset = AVCaptureSessionPresetPhoto
        cameraOutput = AVCapturePhotoOutput()
        
        let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        if let input = try? AVCaptureDeviceInput(device: device) {
            if (captureSesssion.canAddInput(input)) {
                captureSesssion.addInput(input)
                if (captureSesssion.canAddOutput(cameraOutput)) {
                    
                    captureSesssion.addOutput(cameraOutput)
                    previewLayer = AVCaptureVideoPreviewLayer(session: captureSesssion)

                    previewLayer.frame = previewView.bounds
                    
                    previewView.layer.addSublayer(previewLayer)
                    
                    captureSesssion.startRunning()
                    
                    self.onThirtySecondTimer = false
                    startThirtySecondCapture()
                }
            } else {
                print("issue here : captureSesssion.canAddInput")
            }
        } else {
            print("some problem here")
        }
        

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: Actions
    //Calculate when the first 30 second interval should start
    func startThirtySecondCapture(){
        if let datetime = self.trueTimeClient?.referenceTime?.now() {
            let calendar = Calendar.current
            let seconds = calendar.component(.second, from: datetime)
            let offset = (30 - (seconds % 30))
            self.timer = Timer.scheduledTimer(timeInterval: TimeInterval(offset), target: self, selector: (#selector(ImageCaptureViewController.takePicture)), userInfo: nil, repeats: false)
        }
    }
    
    
    func takePicture(){
        if !onThirtySecondTimer {
            self.timer = Timer.scheduledTimer(timeInterval: 30, target: self, selector: (#selector(ImageCaptureViewController.takePicture)), userInfo: nil, repeats: true)
            self.onThirtySecondTimer = true
        }
        
        let settings = AVCapturePhotoSettings()
        let previewPixelType = settings.availablePreviewPhotoPixelFormatTypes.first!
        let previewFormat = [
            kCVPixelBufferPixelFormatTypeKey as String: previewPixelType,
            kCVPixelBufferWidthKey as String: 160,
            kCVPixelBufferHeightKey as String: 160
        ]
        settings.previewPhotoFormat = previewFormat
        cameraOutput.capturePhoto(with: settings, delegate: self)
        
    }
    
    // callBack from take picture
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        
        if let error = error {
            print("error occure : \(error.localizedDescription)")
        }
        
        if  let sampleBuffer = photoSampleBuffer,
            let previewBuffer = previewPhotoSampleBuffer,
            let dataImage =  AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer:  sampleBuffer, previewPhotoSampleBuffer: previewBuffer) {
            
            let dataProvider = CGDataProvider(data: dataImage as CFData)
            let cgImageRef: CGImage! = CGImage(jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            let image = UIImage(cgImage: cgImageRef, scale: 1.0, orientation: UIImageOrientation.right)
            
            self.capturedImage.image = image
            
            var fileName : URL
            if let data = UIImageJPEGRepresentation(image, 0.8) {
                fileName = getDocumentsDirectory().appendingPathComponent("copy.png")
                try? data.write(to: fileName)
            } else {
                print("could not convert image data to jpg")
                return
            }
            
            
            if let date = self.trueTimeClient?.referenceTime?.now(){
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'hh:mm:ss"
                dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
                let dateString = dateFormatter.string(from: date)
                
                let uploadRequest = AWSS3TransferManagerUploadRequest()
                uploadRequest?.bucket = "cu-sky-imager"
                uploadRequest?.key = dateString
                uploadRequest?.body = fileName
                
                transferManager.upload(uploadRequest!).continueWith(executor: AWSExecutor.mainThread(), block: { (task:AWSTask<AnyObject>) -> Any? in
                    print("Uploaded")
                })
            } else {
                print("Unable to get time from TrueTime client. Could not upload image")
            }
        } else {
            print("some error here")
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }




}
