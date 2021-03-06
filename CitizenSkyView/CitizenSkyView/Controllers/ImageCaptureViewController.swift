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
import CoreLocation


class ImageCaptureViewController: UIViewController, AVCapturePhotoCaptureDelegate  {
    
    
    //MARK: Properties
    var captureSesssion : AVCaptureSession!
    var cameraOutput : AVCapturePhotoOutput!
    var previewLayer : AVCaptureVideoPreviewLayer!
    
    var credentialProvider : AWSCognitoCredentialsProvider!
    var configuration : AWSServiceConfiguration!
    var transferManager : AWSS3TransferManager!
    
    var trueTimeClient : TrueTimeClient?
    var timer = Timer()
    var countdownTimer = Timer()
    
    var onThirtySecondTimer = false
    var onCoundownSeconds = false
    var secondsTilStart : TimeInterval?
    
    var manager : LocationService?
    var mostRecentLocation : CLLocation?
    
    var cameraId : String?
    var imageNumber = 0
    
    var event : Event?
    var eventHappening = false
    
    
    @IBOutlet weak var timeRemaining : UILabel!
    @IBOutlet weak var countdownLabel : UILabel!
    @IBOutlet weak var centerText : UILabel!


    override func viewDidLoad() {
        super.viewDidLoad()
        guard let event = self.event else {
            fatalError("Expected event")
        }
        guard let dictionary = Bundle.main.infoDictionary else {
            fatalError("Found no configuration")
        }
        guard let identityPoolId = dictionary["AWS_COGNITO_IDENTITY"] else{
            fatalError("Found no configuration for AWS_COGNITO_IDENTITY")
        }
        guard let manager = self.manager else {
            fatalError("Expected location manager")
        }
        if let eventKey = event.eventRef {
            if eventKey == 2 {
                //Event is in the past. Don't set anything up
                pastEvent()
                return
            }
        }
        credentialProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                           identityPoolId:identityPoolId as! String)
        configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        transferManager = AWSS3TransferManager.default()
        
        trueTimeClient = TrueTimeClient.sharedInstance
        
        
        captureSesssion = AVCaptureSession()
        captureSesssion.sessionPreset = AVCaptureSessionPresetPhoto
        cameraOutput = AVCapturePhotoOutput()
        
        onThirtySecondTimer = false
        onCoundownSeconds = false
        
        
        if (CLLocationManager.headingAvailable()) {
            manager.startUpdatingCompassHeading()
        } else {
            print("compass data not available")
        }
        
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let path = dir.appendingPathComponent("cameraId.txt")
            do {
                let text = try String(contentsOf: path, encoding: String.Encoding.utf8)
                self.cameraId = text
                print("found camera id: " + self.cameraId!)
            } catch {
                print("error reading from camera id file. assigning new value")
                self.cameraId = UUID().uuidString
                print("New camera id: " + self.cameraId!)
            }
        }
        
        
        let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        if let input = try? AVCaptureDeviceInput(device: device) {
            if (captureSesssion.canAddInput(input)) {
                captureSesssion.addInput(input)
                if (captureSesssion.canAddOutput(cameraOutput)) {
                    
                    captureSesssion.addOutput(cameraOutput)
                    
                    captureSesssion.startRunning()
                    
                    self.onThirtySecondTimer = false
                    if let now = self.trueTimeClient?.referenceTime?.now() {
                        if let start = event.startDate, let end = event.endDate {
                            if now > start && now < end {
                                self.timeRemaining.isHidden = true
                                self.countdownLabel.isHidden = true
                                self.eventHappening = true
                                startThirtySecondCapture()
                            } else {
                                startCountdown()
                                
                            }
                        }
                    }
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
    
    //Lock to portrait mode
    open override var shouldAutorotate: Bool {
        get {
            return false
        }
    }
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask{
        get {
            return .portrait
        }
    }
    
    //MARK: Actions
    @IBAction func returnToMainPage(){
        print("Invalidating timers")
        self.timer.invalidate()
        self.countdownTimer.invalidate()
        self.dismiss(animated: true, completion: nil)
    }
    
    
    func pastEvent() {
        self.countdownLabel.text = "Event has finished"
        self.countdownLabel.sizeToFit()
        self.countdownLabel.center.x = self.view.center.x
        self.centerText.isHidden = true
        self.timeRemaining.isHidden = true
    }
    
    func startCountdown(){
        guard let event = self.event else {
            fatalError("Expected Event")
        }
        if let datetime = self.trueTimeClient?.referenceTime?.now(), let start = event.startDate {
            let diff = start.timeIntervalSince(datetime)

            self.secondsTilStart = diff
            
            //set image capture timer
            self.timer = Timer.scheduledTimer(timeInterval: diff, target: self, selector: (#selector(ImageCaptureViewController.takePicture)), userInfo: nil, repeats: false)


            if diff > 86400 {                                   //Number of seconds in 24 hours
                let days = Int(diff / 86400)
                self.timeRemaining.text = String(days) + " days"
            } else {
                
                //start countdown timer
                self.countdownTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(ImageCaptureViewController.updateCountdown)), userInfo: nil, repeats: true)
                self.timeRemaining.text = timeString(time: self.secondsTilStart!)
                self.timeRemaining.sizeToFit()
                self.timeRemaining.center.x = self.view.center.x
            }
            
        } else {
            print("unable to align time with true time client.")
            //This is acutally a error case now, handle it
        }
    }
    
    func updateCountdown(){
        guard let event = self.event else {
            fatalError("Expected Event")
        }
        //Change structure to check for image capture first
        if self.eventHappening {
            //Image capture has started, hide countdown
            self.countdownTimer.invalidate()
            self.countdownLabel.isHidden = true
            self.timeRemaining.isHidden = true
        } else {
            if let curr = self.trueTimeClient?.referenceTime?.now(), let start = event.startDate{
                self.secondsTilStart = start.timeIntervalSince(curr)
                self.timeRemaining.text = timeString(time: self.secondsTilStart!)
                self.timeRemaining.sizeToFit()
                self.timeRemaining.center.x = self.view.center.x
            } else {
                print("unable to decrement time due to nil true time client reference time")
            }
        }
    }
    
    func timeString(time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02i:%02i:%02i", hours, minutes, seconds)
    }
    
    
    //Calculate when the first 30 second interval should start
    func startThirtySecondCapture(){
        if let datetime = self.trueTimeClient?.referenceTime?.now() {
            let calendar = Calendar.current
            let seconds = calendar.component(.second, from: datetime)
            let nanosecs = Double(calendar.component(.nanosecond, from: datetime)) / Double(1000000000)
            let offset = Double((30 - (seconds % 30))) - nanosecs
            self.timer = Timer.scheduledTimer(timeInterval: TimeInterval(offset), target: self, selector: (#selector(ImageCaptureViewController.takePicture)), userInfo: nil, repeats: false)
            self.onThirtySecondTimer = false
        }
    }
    
    
    func takePicture(){
        guard let event = self.event else {
            fatalError("Expected Event")
        }
        self.eventHappening = true
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
        if let now = self.trueTimeClient?.referenceTime?.now(), let end = event.endDate {
            if now > end {
                //Event is over!
                self.timer.invalidate()
                self.centerText.text = "Event complete!"
                self.centerText.isHidden = false
            }
        }
    }
    
    // callBack from take picture
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        print("Image Captured")
        if let error = error {
            print("error : \(error.localizedDescription)")
        }
        guard let manager = self.manager else {
            print("Expected location manager")
            return
        }
        guard let eventName = self.event?.EventName else {
            print("No valid event name")
            return
        }
        if let date = self.trueTimeClient?.referenceTime?.now() {
            if  let sampleBuffer = photoSampleBuffer,
                let previewBuffer = previewPhotoSampleBuffer,
                let dataImage =  AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer:  sampleBuffer, previewPhotoSampleBuffer: previewBuffer) {
                
                let dataProvider = CGDataProvider(data: dataImage as CFData)
                let cgImageRef: CGImage! = CGImage(jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                let image = UIImage(cgImage: cgImageRef, scale: 1.0, orientation: UIImageOrientation.right)
                
                var metadata = [String: String]()
                var fileName : URL
                if let data = UIImageJPEGRepresentation(image, 0.8) {
                    metadata["size"] = String(data.count)
                    fileName = getDocumentsDirectory().appendingPathComponent("copy.png")
                    try? data.write(to: fileName)
                } else {
                    print("could not convert image data to jpg")
                    return
                }
            
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'hh:mm:ss"
                dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
                let dateString = dateFormatter.string(from: date)
                
                
                metadata["timestamp"] = dateString
                metadata["filetype"] = "JPEG"
                metadata["sizex"] = String(describing: image.size.width)
                metadata["sizey"] = String(describing: image.size.height)
                
                metadata["heading"] = String(describing: manager.getCurrentHeading())
                
                if let location = self.mostRecentLocation {
                    metadata["lat"] = String(location.coordinate.latitude)
                    metadata["lon"] = String(location.coordinate.longitude)
                } else {
                    print("Last location unknown")
                }
                
                
                let uploadRequest = AWSS3TransferManagerUploadRequest()
                uploadRequest?.bucket = "citizenskyview"
                //Camera id is guarunteed to be not nil
                uploadRequest?.key = eventName + "/" + cameraId! + "_" + dateString
                uploadRequest?.body = fileName
                uploadRequest?.metadata = metadata
                imageNumber += 1
                transferManager.upload(uploadRequest!).continueWith(executor: AWSExecutor.mainThread(), block: { (task:AWSTask<AnyObject>) -> Any? in
                    if let error = task.error as NSError? {
                        if error.domain == AWSS3TransferManagerErrorDomain, let code = AWSS3TransferManagerErrorType(rawValue: error.code) {
                            switch code {
                            case .cancelled, .paused:
                                break
                            default:
                                print("Error uploading: \(String(describing: uploadRequest?.key)) Error: \(error)")
                            }
                        } else {
                            print("Error uploading: \(String(describing: uploadRequest?.key)) Error: \(error)")
                        }
                        return nil
                    }
                    
                    print("Upload complete for: \(String(describing: uploadRequest?.key))")
                    return nil
                })

            } else {
                print("unable to get image data from image data buffers")
            }
        } else {
            print("Could not get reference time from true time client")
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }




}
