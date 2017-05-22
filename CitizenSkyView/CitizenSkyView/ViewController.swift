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
    

    @IBOutlet weak var eventSpinner: UIActivityIndicatorView!
    @IBOutlet weak var readyButton: UIButton!



    override func viewDidLoad() {
        super.viewDidLoad()
        readyButton.isHidden = true
        eventSpinner.startAnimating()
        eventSpinner.hidesWhenStopped = true
        credentialProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                            identityPoolId:"us-west-2:43473766-619f-4209-996b-7dc61e65ccf1")
        configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration

        
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
                            if let start = dateFormatter.date(from: event.Start!), let end = dateFormatter.date(from: event.End!){
                                if now > start && now < end {
                                    print("The event is now!")
                                    self.eventSpinner.stopAnimating()
                                    self.readyButton.isHidden = false
                                    self.eventStart = start
                                    self.eventEnd = end
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

