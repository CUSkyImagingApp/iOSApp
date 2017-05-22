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

class ViewController: UIViewController {
    
    
    //MARK: Properties
    
    var credentialProvider : AWSCognitoCredentialsProvider!
    var configuration : AWSServiceConfiguration!
    var dynamoDBObjectMapper : AWSDynamoDBObjectMapper?
    
    var trueTimeClient : TrueTimeClient?
    
    var eventStart : Date?
    var eventEnd : Date?
    var eventName : String?
    var eventOccuring = false

    @IBOutlet weak var eventSpinner: UIActivityIndicatorView!
    @IBOutlet weak var readyButton: UIButton!
    @IBOutlet weak var eventInfo : UILabel!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!


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
        
        
        //self.eventSpinner.stopAnimating()
        //self.readyButton.isHidden = false
        //self.eventStart = start
        //self.eventEnd = end
        
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
                                        self.eventSpinner.stopAnimating()
                                        self.readyButton.isHidden = false
                                        if let eventName = event.EventName {
                                            self.eventInfo.text = eventName + " is currently running"
                                            self.eventInfo.sizeToFit()
                                        } else {
                                            self.eventInfo.text = "There is currently an ongoing event. \nClick the button below to start taking pictures"
                                            self.eventInfo.sizeToFit()
                                        }
                                        print("Event happening")
                                        self.eventInfo.center.x = self.view.center.x
                                        
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
                            if let start = self.eventStart, let end = self.eventEnd {
                                //This is the soonest event
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
        //Ask for camera permission
        askPermission()

        
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
    
    //MARK: Actions
    
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
                        let alert = UIAlertController(title: "Camera Needed!" , message:  "The camera is the main feature of our application", preferredStyle: .alert)
                        let action = UIAlertAction(title: "Ok", style: .cancel, handler: nil)
                        alert.addAction(action)
                        self?.present(alert, animated: true, completion: nil)  
                    } 
                }
            });
        }
    }
    

}

