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
    
    var startDate : Date?
    var endDate : Date?
    var dateString : String?
    var timeString : String?
    var eventRef : Int?
    
    class func dynamoDBTableName() -> String {
        return "Event"
    }
    
    class func hashKeyAttribute() -> String {
        return "EventName"
    }
    
    func populateCustomVars(now: Date){
        //Date creation
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        if let start = dateFormatter.date(from: Start!){
            startDate = start
        } else {
            print("Unable to convert string into date object")
            if let startString = Start {
                print(startString)
            } else {
                print("Start is nil")
            }
        }
        if let end = dateFormatter.date(from: End!){
            endDate = end
        } else {
            print("unable to convert string into date object")
            if let endString = End {
                print(endString)
            } else {
                print("End is nil")
            }
        }
        //Date and time string creation
        dateFormatter.dateFormat = "MMM d, yyyy"
        let calendar = Calendar.current
        if let sdate = startDate, let edate = endDate {
            dateString = dateFormatter.string(from: sdate)
            let smin = calendar.component(.minute, from: sdate)
            let emin = calendar.component(.minute, from: edate)
            var stime : String
            var etime : String
            if smin == 0 {
                dateFormatter.dateFormat = "h a"
                stime = dateFormatter.string(from: sdate)
            } else {
                dateFormatter.dateFormat = "h:mm a"
                stime = dateFormatter.string(from: sdate)
            }
            if emin == 0 {
                dateFormatter.dateFormat = "h a"
                etime = dateFormatter.string(from: edate)
            } else {
                dateFormatter.dateFormat = "h:mm a"
                etime = dateFormatter.string(from: edate)
            }
            self.timeString = stime + " - " + etime
        } else {
            print("unable to create datestring because startDate or endDate is nil")
        }
        
        //Determine past present or future event
        if let end = endDate, let start = startDate {
            if start < now {
                if end < now {
                    //past event
                    eventRef = 2
                } else {
                    //current event
                    eventRef = 1
                }
            } else {
                //future event
                eventRef = 0
            }
        } else {
            print("unable to get start and end date")
        }
    }
    
}
