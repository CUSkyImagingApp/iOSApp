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
import AWSDynamoDB
import AVFoundation
import TrueTime
import CoreLocation

class ViewController: UIViewController,  CLLocationManagerDelegate{
    
    
    //MARK: Properties
    
    var credentialProvider : AWSCognitoCredentialsProvider!
    var configuration : AWSServiceConfiguration!
    var dynamoDBObjectMapper : AWSDynamoDBObjectMapper?
    
    var trueTimeClient : TrueTimeClient?
    
    var eventStart : Date?
    var eventEnd : Date?
    var eventName : String?
    var eventOccuring = false
    
    var manager : CLLocationManager?
    
    var cameraAuthorized = false
    var locationAuthorized = false
    
    let refreshNotification = Notification.Name(rawValue: "refresh")

    @IBOutlet weak var eventSpinner: UIActivityIndicatorView!
    @IBOutlet weak var readyButton: UIButton!
    @IBOutlet weak var eventInfo : UILabel!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var settingsButton: UIButton!
    


    override func viewDidLoad() {
        super.viewDidLoad()
        readyButton.isHidden = true
        eventSpinner.startAnimating()
        eventSpinner.hidesWhenStopped = true
        dateLabel.isHidden = true
        timeLabel.isHidden = true
        credentialProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                            identityPoolId:"us-west-2:43473766-619f-4209-996b-7dc61e65ccf1")
        configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration

        
        dynamoDBObjectMapper = AWSDynamoDBObjectMapper.default()
        
        trueTimeClient = TrueTimeClient.sharedInstance
        trueTimeClient?.start()
        
        let nc = NotificationCenter.default
        nc.addObserver(forName: refreshNotification, object: nil, queue: nil, using: refreshPage)
        
        manager = CLLocationManager()
        manager?.delegate = self
        
        getEventsFromDynamoDB()
        askPermission()
        initCameraId()
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "InitiateEvent" {
            if let destination = segue.destination as? ImageCaptureViewController {
                destination.eventStart = self.eventStart
                destination.eventEnd = self.eventEnd
            }
        }
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
    func initCameraId() -> Void {
        let file = "cameraId.txt"
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let path = dir.appendingPathComponent(file)
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: path.path) {
                let cameraId = UUID().uuidString
                print("CameraId: " + cameraId)
                do {
                    try cameraId.write(to: path, atomically: false, encoding: String.Encoding.utf8)
                }
                catch {
                    print("error writing camera id file")
                }
            } else {
                print("camera id already assigned")
            }
        }
    }
    
    func refreshPage(notification: Notification) -> Void{
        print("refresh")
        getEventsFromDynamoDB()
        askPermission()
    }
    
    func getEventsFromDynamoDB() {
        self.eventSpinner.startAnimating()
        self.eventInfo.text = "Searching for Upcoming Events"
        self.dateLabel.isHidden = true
        self.timeLabel.isHidden = true
        self.readyButton.isHidden = true
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
                            if let start = dateFormatter.date(from: event.Start!), let end = dateFormatter.date(from: event.End!){
                                if now < end {
                                    //The event is in progress or hasn't started
                                    if now > start {
                                        //event is now, this is the event we should start
                                        self.eventOccuring = true
                                        self.eventStart = start
                                        self.eventEnd = end
                                        self.eventName = event.EventName
                                        self.displayEvent()
                                        
                                    } else if let savedStart = self.eventStart{
                                        if start < savedStart {
                                            //This event will happen sooner, this is candidate
                                            self.eventStart = start
                                            self.eventEnd = end
                                            self.eventName = event.EventName
                                        }
                                    } else {
                                        //Not a current event and also must be the first event in the table, so just save it as the candidate
                                        self.eventStart = start
                                        self.eventEnd = end
                                        self.eventName = event.EventName
                                    }
                                }
                            } else {
                                print("unable to convert start and/or end date into datetime object")
                                
                            }
                            
                        }
                        //Have parsed through all events
                        self.eventSpinner.stopAnimating()
                        if !self.eventOccuring {
                            self.displayEvent()
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

    }
    // This method you can use somewhere you need to know camera permission   state
    func askPermission() {
        let cameraPermissionStatus =  AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        
        switch cameraPermissionStatus {
        case .authorized:
            self.cameraAuthorized = true
            print("Already Authorized")
        case .denied:
            self.cameraAuthorized = false
            print("denied")
            noCameraPermission()
        case .restricted:
            self.cameraAuthorized = false
            print("restricted")
            noCameraPermission()
        default:
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: {
                [weak self]
                (granted :Bool) -> Void in
                
                if granted == true {
                    // User granted
                    print("User granted")
                    self?.cameraAuthorized = true
                }
                else {
                    // User Rejected
                    print("User Rejected")
                    self?.cameraAuthorized = false
                    self?.noCameraPermission()
                }
            })
        }
        
        let locationPermissionStatus = CLLocationManager.authorizationStatus()
        
        switch locationPermissionStatus {
        case .notDetermined:
            self.manager?.requestWhenInUseAuthorization()
            break
        case .authorizedWhenInUse:
            print("Already authorized when in use")
            self.locationAuthorized = true
            break
        case .denied:
            print("Denied location access")
            self.locationAuthorized = false
            self.noLocationPermission()
            break
        case .restricted:
            print("location access restricted")
            self.locationAuthorized = false
            self.noLocationPermission()
            break
        case .authorizedAlways:
            print("Always authorized")
            self.locationAuthorized = true
            break
        }
    
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .denied || status == .restricted {
            self.locationAuthorized = false
            self.noLocationPermission()
        } else if status == .authorizedAlways || status == .authorizedWhenInUse {
            self.locationAuthorized = true
        } else {
            self.manager?.requestWhenInUseAuthorization()
        }
    }
    
    func displayEvent(){
        if !self.cameraAuthorized || !self.locationAuthorized {
            return
        }
        self.settingsButton.isHidden = true
        if !self.eventOccuring {
            if let start = self.eventStart, let end = self.eventEnd {
                //This is the soonest event
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d, yyyy"
                self.dateLabel.isHidden = false
                self.dateLabel.text = dateFormatter.string(from: start)
                self.dateLabel.sizeToFit()
                dateFormatter.dateFormat = "HH:mm"
                let startTime = dateFormatter.string(from: start)
                let endTime = dateFormatter.string(from: end)
                self.timeLabel.isHidden = false
                self.timeLabel.text = startTime + " - " + endTime
                self.timeLabel.sizeToFit()
                if let eventName = self.eventName {
                    self.eventInfo.text = eventName + " will occur"
                } else {
                    self.eventInfo.text = "The next event will occur"
                }
                self.eventInfo.sizeToFit()
                self.eventInfo.center.x = self.view.center.x
                self.dateLabel.center.x = self.view.center.x
                self.timeLabel.center.x = self.view.center.x
                //TODO: Don't enable if event is more than 24 hours out
                self.readyButton.isHidden = false
            } else {
                self.eventInfo.text = "There are no upcoming events"
                self.eventInfo.sizeToFit()
                self.eventInfo.center.x = self.view.center.x
            }
        } else {
            self.readyButton.isHidden = false
            if let eventName = self.eventName {
                self.eventInfo.text = eventName + " is currently running"
                self.eventInfo.sizeToFit()
            } else {
                self.eventInfo.text = "There is currently an ongoing event. \nClick the button below to start taking pictures"
                self.eventInfo.sizeToFit()
            }
            self.eventInfo.center.x = self.view.center.x
        }

    }
    
    func noCameraPermission() {
        self.eventInfo.text = "CitizenSkyView need access to the camera"
        self.eventInfo.isHidden = false
        self.dateLabel.text = "Please enable camera access in settings"
        self.dateLabel.isHidden = false
        self.timeLabel.isHidden = true
        self.eventInfo.sizeToFit()
        self.dateLabel.sizeToFit()
        self.eventInfo.center.x = self.view.center.x
        self.dateLabel.center.x = self.view.center.x
        self.readyButton.isHidden = true
        self.settingsButton.isHidden = false
    }
    
    func noLocationPermission() {
        self.eventInfo.text = "CitizenSkyView need access your location"
        self.eventInfo.isHidden = false
        self.dateLabel.text = "Please enable location access in settings"
        self.dateLabel.isHidden = false
        self.timeLabel.isHidden = true
        self.eventInfo.sizeToFit()
        self.dateLabel.sizeToFit()
        self.eventInfo.center.x = self.view.center.x
        self.dateLabel.center.x = self.view.center.x
        self.readyButton.isHidden = true
        self.settingsButton.isHidden = false
    }
    
    
    @IBAction func returnFromEvent(segue:UIStoryboardSegue){
        //Re check for events
        print("returned from event page")
        getEventsFromDynamoDB()
    }
    
    @IBAction func goToSettings(){
        if let appSettings = URL(string:UIApplicationOpenSettingsURLString){
            UIApplication.shared.open(appSettings)
        }
        
    }
    

}

