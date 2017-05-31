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
    
    var hasPermissions = false
    
    var events = [[Event](), [Event](), [Event]()]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        credentialProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                           identityPoolId:"us-west-2:43473766-619f-4209-996b-7dc61e65ccf1")
        configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        dynamoDBObjectMapper = AWSDynamoDBObjectMapper.default()
        
        trueTimeClient = TrueTimeClient.sharedInstance
        trueTimeClient?.start()
        
        getEventsFromDynamoDB()
        hasPermissions = askPermission()
        
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
            guard let imageCaptureViewController = segue.destination as? ImageCaptureViewController else {
                fatalError("Unexpected destination: \(segue.destination)")
            }
            guard let selectedEventCell = sender as? EventTableViewCell else {
                fatalError("Unexpected sender: \(String(describing: sender))")
            }
            guard let indexPath = tableView.indexPath(for: selectedEventCell) else {
                fatalError("The selected cell is not being displayed by the table")
            }
            let selectedEvent = events[indexPath.section][indexPath.row]
            imageCaptureViewController.event = selectedEvent
        }

    }
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == "EventSegue" {
            if self.askPermission() {
                return true
            } else {
                self.showPermissionsModal()
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
        var hasCameraPermission = false
        var hasLocationPermission = false
        let cameraPermissionStatus =  AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        if cameraPermissionStatus == .authorized {
            hasCameraPermission = true
        } else {
            hasCameraPermission = false
        }
        
        let locationPermissionStatus = CLLocationManager.authorizationStatus()
        if locationPermissionStatus == .authorizedAlways || locationPermissionStatus == .authorizedWhenInUse {
            hasLocationPermission = true
        } else {
            hasLocationPermission = false
        }
        
        if !hasLocationPermission || !hasCameraPermission {
            return false
        } else {
            return true
        }
    }
    

    
    func showPermissionsModal() -> Void {
        performSegue(withIdentifier: "PermissionsSegue", sender: self)
    }
    
    @IBAction func unwindToEventTable(segue: UIStoryboardSegue) {
        
    }
    
}
