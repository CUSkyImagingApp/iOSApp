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
    
    var events : [Event] = [Event]()
    
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

        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return events.count
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "EventTableViewCell"
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as? EventTableViewCell else {
            fatalError("The dequeued cell is not an instance of MealTableViewCell.")
        }
        let event = events[indexPath.row]
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
                        print(paginatedOutput.items.count)
                        for event in paginatedOutput.items as! [Event]{
                            event.populateCustomVars()
                            self.events += [event]
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
    
}
