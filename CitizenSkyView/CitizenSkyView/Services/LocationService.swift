//
//  LocationService.swift
//  
//
//  Created by Jeremy Rapp on 6/25/17.
//
//

import Foundation
import CoreLocation



class LocationService: NSObject, CLLocationManagerDelegate {
    
    
    private var manager : CLLocationManager?
    private var heading : CLHeading?
    private var authorized : CLAuthorizationStatus?
    private var location : CLLocation?
    
    override init() {
        super.init()
        self.manager = CLLocationManager()
        self.manager?.delegate = self
    }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        //Dismiss heading calibration after minute if the calibration is not complete
        Timer.scheduledTimer(timeInterval: 60, target: self, selector: (#selector(LocationService.dismissHeadingCalibration)), userInfo: nil, repeats: false)
        return true
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.heading = newHeading
        let nc = NotificationCenter.default
        nc.post(name: Notification.Name(rawValue: "newHeadingUpdate"), object: newHeading)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.location = locations.last
    }
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        print("Did finish deffered updates with error: \(String(describing: error))")
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("did fail with error \(String(describing: error))")
    }
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.authorized = status
        let nc = NotificationCenter.default
        nc.post(name: Notification.Name(rawValue:"locationAuthChange"), object: status)
    }
    func dismissHeadingCalibration() -> Void {
        guard let manager = self.manager else {
            fatalError("Expected location manager")
        }
        manager.dismissHeadingCalibrationDisplay()
    }
    func getCurrentLocation() -> CLLocation? {
        if let location = self.location {
            return location
        } else {
            print("No location is available yet")
            return nil
        }
    }
    func requestLocationPermission() -> Void {
        guard let manager = self.manager else {
            fatalError("Expected location manager")
        }
        self.authorized = CLLocationManager.authorizationStatus()
        if let auth = self.authorized {
            if auth == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else if auth == .denied || auth == .restricted{
                print("Location is blocked")
            } else {
                print("location is authorized")
            }
        }
    }
    func getAuthorizationStatus() -> CLAuthorizationStatus {
        if let auth = self.authorized {
            return auth
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }
    func locationServicesEnabled() -> Bool {
        return CLLocationManager.locationServicesEnabled()
    }
    func requestLocation() -> Void {
        guard let manager = self.manager else {
            fatalError("Expected Manager")
        }
        manager.requestLocation()
    }
    func startUpdatingCompassHeading() -> Void {
        guard let manager = self.manager else {
            fatalError("Expected location manager")
        }
        manager.startUpdatingHeading()
    }
    func stopUpdatingCompassHeading() -> Void {
        guard let manager = self.manager else {
            fatalError("Expected location manager")
        }
        manager.stopUpdatingHeading()
    }
    
    func getCurrentHeading() -> CLHeading? {
        if let heading = self.heading {
            return heading
        } else {
            print("no heading available")
            return nil
        }
    }

    
}
