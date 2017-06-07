//
//  PermissionsViewController.swift
//  CitizenSkyView
//
//  Created by Jeremy Rapp on 5/27/17.
//  Copyright © 2017 CET. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import CoreLocation


class PermissionsViewController : UIViewController, CLLocationManagerDelegate {
    
    var manager : CLLocationManager?
    
    let noCameraText = "CitizenSkyView needs access to your camera during each event. Without access to the camera CitizenSkyView has no function."
    let noLocationText = "CitizenSkyView needs your location once during each event. This information allows scientists can stitch image sequences together accurately."
    let noCameraHead = "Why does CitizenSkyView need my camera?"
    let noLocationHead = "Why does CitizenSkyView Need my location?"
    
    
    @IBOutlet weak var message : UILabel!
    @IBOutlet weak var locDetailHeading : UILabel!
    @IBOutlet weak var locDetailBody : UILabel!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        manager = CLLocationManager()
        manager?.delegate = self
        let cameraPermission = askCameraPermission()
        let locationPermission = askLocationPermission()
        
        if !cameraPermission && !locationPermission {
            message.text = "CitizenSkyView needs to access your camera and location information to function. Please enable these in settings"
            locDetailBody.isHidden = false
            locDetailBody.text = self.noLocationText
            locDetailHeading.isHidden = false
            locDetailHeading.text = self.noLocationHead
        } else if !cameraPermission {
            message.text = "CitizenSkyView needs to access your camera to function. Please enable these in settings"
            locDetailBody.isHidden = false
            locDetailBody.text = self.noCameraText
            locDetailHeading.isHidden = false
            locDetailHeading.text = self.noCameraHead
        } else if !locationPermission {
            message.text = "CitizenSkyView needs to access your location information to function. Please enable these in settings."
            locDetailBody.isHidden = false
            locDetailBody.text = self.noLocationText
            locDetailHeading.isHidden = false
            locDetailHeading.text = self.noLocationHead
        } else {
            self.performSegue(withIdentifier: "EventSegue", sender: self)
        }

        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func askCameraPermission() -> Bool {
        var hasPermission = false
        let cameraPermissionStatus = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        
        switch cameraPermissionStatus {
        case .authorized:
            hasPermission = true
        case .denied:
            hasPermission = false
        case .restricted:
            hasPermission = false
        default:
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: {
                [weak self]
                (granted :Bool) -> Void in
                if granted == true {
                    hasPermission = true
                } else {
                    hasPermission = false
                }
            })
        }
        return hasPermission
    }
    
    func askLocationPermission() -> Bool {
        guard let manager = self.manager else {
            fatalError("expected location manager")
        }
        var hasPermission = false
        let locationPermissionStatus = CLLocationManager.authorizationStatus()
        switch locationPermissionStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            hasPermission = true
        case .denied, .restricted:
            hasPermission = false
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        }
        return hasPermission
    }
    
    @IBAction func goToSettings() {
        if let appSettings = URL(string: UIApplicationOpenSettingsURLString) {
            UIApplication.shared.open(appSettings)
        }
    }
    
    
}
