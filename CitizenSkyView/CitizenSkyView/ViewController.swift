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
import AWSDynamoDB
import AVFoundation
import TrueTime

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    
    
    //MARK: Properties
    var captureSesssion : AVCaptureSession!
    var cameraOutput : AVCapturePhotoOutput!
    var previewLayer : AVCaptureVideoPreviewLayer!
    
    var credentialProvider : AWSCognitoCredentialsProvider!
    var configuration : AWSServiceConfiguration!
    var transferManager : AWSS3TransferManager!
    var dynamoDBObjectMapper : AWSDynamoDBObjectMapper?
    
    var trueTimeClient : TrueTimeClient?
    
    @IBOutlet weak var capturedImage: UIImageView!
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var eventSpinner: UIActivityIndicatorView!



    override func viewDidLoad() {
        super.viewDidLoad()
        previewView.isHidden = true
        capturedImage.isHidden = true
        eventSpinner.startAnimating()
        eventSpinner.hidesWhenStopped = true
        credentialProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                            identityPoolId:"us-west-2:43473766-619f-4209-996b-7dc61e65ccf1")
        configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        transferManager = AWSS3TransferManager.default()
        
        dynamoDBObjectMapper = AWSDynamoDBObjectMapper.default()
        
        trueTimeClient = TrueTimeClient.sharedInstance
        trueTimeClient?.start()
        

        
        let scanExpression = AWSDynamoDBScanExpression()
        scanExpression.limit = 20
        
        dynamoDBObjectMapper?.scan(Event.self, expression: scanExpression).continueWith(block: {(task:AWSTask<AWSDynamoDBPaginatedOutput>) -> Any? in
            if let error = task.error as NSError? {
                print("The request failed. Error \(error)")
                return ()
            } else if let paginatedOutput = task.result {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                self.trueTimeClient?.fetchIfNeeded { result in
                    switch result {
                    case let .success(referenceTime):
                        let now = referenceTime.now()
                        for event in paginatedOutput.items as! [Event]{
                            print(event.Start!)
                            print(event.End!)
                            print(now)
                            if let start = dateFormatter.date(from: event.Start!), let end = dateFormatter.date(from: event.End!){
                                if now > start && now < end {
                                    print("The event is now!")
                                    self.eventSpinner.stopAnimating()
                                    self.capturedImage.isHidden = false
                                    self.previewView.isHidden = false
                                    
                                } else {
                                    print("The event is not now")
                                    
                                    //TODO: Deal with multiple events in DynamoDB
                                }
                            } else {
                                print("unable to convert start and/or end date into datetime object")
                                
                            }
                            
                        }
                    case let .failure(error):
                        print("Error! \(error)")
                    }
                }
            } else {
                print("There was no error, but the response was empty")

            }
            return ()
        })

        
        
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
                    print(previewView)
                    previewLayer.frame = previewView.bounds
                    
                    previewView.layer.addSublayer(previewLayer)
                    
                    captureSesssion.startRunning()
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
    @IBAction func takePicture(_ sender: UIButton){
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
            print(UIImage(data: dataImage)?.size as Any)
            
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
                dateFormatter.dateFormat = "ss:mm:hh'T'dd-MM-yyyy"
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
    
    // This method you can use somewhere you need to know camera permission   state
    func askPermission() {
        let cameraPermissionStatus =  AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        
        switch cameraPermissionStatus {
        case .authorized:
            print("Already Authorized")
        case .denied:
            print("denied")
            
            let alert = UIAlertController(title: "Sorry :(" , message: "But  could you please grant permission for camera within device settings",  preferredStyle: .alert)
            let action = UIAlertAction(title: "Ok", style: .cancel,  handler: nil)
            alert.addAction(action)
            present(alert, animated: true, completion: nil)
            
        case .restricted:
            print("restricted")
        default:
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: {
                [weak self]
                (granted :Bool) -> Void in
                
                if granted == true {
                    // User granted
                    print("User granted")
                    DispatchQueue.main.async(){
                        //Do smth that you need in main thread
                    }
                }
                else {
                    // User Rejected
                    print("User Rejected")
                    
                    DispatchQueue.main.async(){
                        let alert = UIAlertController(title: "WHY?" , message:  "Camera it is the main feature of our application", preferredStyle: .alert)
                        let action = UIAlertAction(title: "Ok", style: .cancel, handler: nil)
                        alert.addAction(action)
                        self?.present(alert, animated: true, completion: nil)  
                    } 
                }
            });
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }


}

