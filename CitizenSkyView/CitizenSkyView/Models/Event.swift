//
//  Event.swift
//  
//
//  Created by Jeremy on 5/17/17.
//
//

import Foundation
import AWSDynamoDB


class Event : AWSDynamoDBObjectModel, AWSDynamoDBModeling {
    var EventName : String?
    var Start : String?
    var End : String?
    
    class func dynamoDBTableName() -> String {
        return "Event"
    }
    
    class func hashKeyAttribute() -> String {
        return "EventName"
    }
    
}
