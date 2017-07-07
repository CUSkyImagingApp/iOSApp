//
//  EventTableViewController.swift
//  CitizenSkyView
//
//  Created by Jeremy Rapp on 5/26/17.
//  Copyright © 2017 CET. All rights reserved.
//

import Foundation
import UIKit
import AWSCore
import AWSCognito
import AWSDynamoDB
import AVFoundation
import TrueTime
import CoreLocation

class EventTableViewController: UITableViewController {
    
    var credentialProvider : AWSCognitoCredentialsProvider!
    var configuration : AWSServiceConfiguration!
    var dynamoDBObjectMapper : AWSDynamoDBObjectMapper?
    var trueTimeClient : TrueTimeClient?

    var manager : LocationService?
    
    var hasPermissions = false
    
    var events = [[Event](), [Event](), [Event]()]
    
    let refreshNotification = Notification.Name(rawValue: "refresh")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let dictionary = Bundle.main.infoDictionary else {
            fatalError("Found no configuration")
        }
        guard let identityPoolId = dictionary["AWS_COGNITO_IDENTITY"] else{
            fatalError("Found no configuration for AWS_COGNITO_IDENTITY")
        }
        credentialProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                           identityPoolId:identityPoolId as! String)
        configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        dynamoDBObjectMapper = AWSDynamoDBObjectMapper.default()
        
        trueTimeClient = TrueTimeClient.sharedInstance
        trueTimeClient?.start()
        
        manager = LocationService()
        
        let nc = NotificationCenter.default
        nc.addObserver(forName: refreshNotification, object: nil, queue: nil, using: refreshPage)
        
        getEventsFromDynamoDB()
        initCameraId()
        hasPermissions = askPermission()
        
        self.navigationController?.navigationBar.tintColor = UIColor(displayP3Red: 1, green: 1, blue: 1, alpha: 1.0)
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return events[section].count
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 75
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Future Events"
        case 1:
            return "Ongoing Events"
        case 2:
            return "Past Events"
        default:
            return "Events"
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "EventTableViewCell"
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as? EventTableViewCell else {
            fatalError("The dequeued cell is not an instance of MealTableViewCell.")
        }
        let event = events[indexPath.section][indexPath.row]
        if let eventName = event.EventName {
            cell.eventName.text = eventName
        } else {
            cell.eventName.text = "Default Event"
        }
        if let eventDate = event.dateString {
            cell.eventDate.text = eventDate
        } else {
            cell.eventDate.text = "Unknown Date"
        }
        if let eventTime = event.timeString {
            cell.eventTime.text = eventTime
        } else {
            cell.eventTime.text = "Unknown Time"
        }
        return cell
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if segue.identifier == "EventSegue" {
            guard let compassViewController = segue.destination as? CompassViewController else {
                fatalError("Unexpected destination: \(segue.destination)")
            }
            guard let selectedEventCell = sender as? EventTableViewCell else {
                fatalError("Unexpected sender: \(String(describing: sender))")
            }
            guard let indexPath = tableView.indexPath(for: selectedEventCell) else {
                fatalError("The selected cell is not being displayed by the table")
            }
            let selectedEvent = events[indexPath.section][indexPath.row]
            compassViewController.event = selectedEvent
            compassViewController.manager = self.manager
        } else if segue.identifier == "PermissionsSegue" {
            guard let permissionsViewController = segue.destination as? PermissionsViewController else {
                fatalError("Expected destination controller: \(segue.destination)")
            }
            permissionsViewController.manager = self.manager
        }

    }
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == "EventSegue" {
            if askPermission() {
                return true
            } else {
                showPermissionsModal()
                return false
            }
        } else {
            return true
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
    
    func getEventsFromDynamoDB() {
        let scanExpression = AWSDynamoDBScanExpression()
        scanExpression.limit = 20
        //Clear events
        for index in 0...self.events.count-1 {
            self.events[index].removeAll()
        }
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
                            event.populateCustomVars(now: now)
                            guard let eventRef = event.eventRef else {
                                print("unknown event ref")
                                return
                            }
                            self.events[eventRef] += [event]
                        }
                        self.tableView.reloadData()
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
    func askPermission() -> Bool{
        guard let manager = self.manager else {
            fatalError("expected location manager")
        }
        var hasCameraPermission = false
        var hasLocationPermission = false
        let cameraPermissionStatus =  AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        if cameraPermissionStatus == .authorized {
            hasCameraPermission = true
        } else if cameraPermissionStatus == .notDetermined {
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: {
                (granted :Bool) -> Void in
                if granted == true {
                    hasCameraPermission = true
                } else {
                    hasCameraPermission = false
                }
            })
        }
        else {
            hasCameraPermission = false
        }
        
        let locationPermissionStatus = CLLocationManager.authorizationStatus()
        if locationPermissionStatus == .authorizedAlways || locationPermissionStatus == .authorizedWhenInUse {
            hasLocationPermission = true
        } else if locationPermissionStatus == .notDetermined {
            manager.requestLocationPermission()
        } else {
            hasLocationPermission = false
        }
        
        if !hasLocationPermission || !hasCameraPermission {
            return false
        } else {
            return true
        }
    }
    
    func showPermissionsModal() {
        performSegue(withIdentifier: "PermissionsSegue", sender: self)
    }
    
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
        getEventsFromDynamoDB()
        hasPermissions = askPermission()
    }

    
}
