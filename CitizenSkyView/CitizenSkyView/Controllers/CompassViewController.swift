//
//  CompassViewController.swift
//  CitizenSkyView
//
//  Created by Jeremy Rapp on 7/5/17.
//  Copyright © 2017 CET. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation
import AudioToolbox

class CompassViewController: UIViewController {
    
    var manager : LocationService?
    var event : Event?
    var withinRange = false
    var numberOfVibrate = 0
    var vibrateTimer = Timer()
    
    @IBOutlet weak var degreesLabel : UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let man = self.manager else {
            fatalError("Expected location manager")
        }
        addCompassObserver()
        man.requestLocation()
        man.startUpdatingCompassHeading()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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
    
    func addCompassObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(CompassViewController.updateCompassHeading), name: Notification.Name("newHeadingUpdate"), object: nil)
    }
    
    func removeCompassObserver() {
        NotificationCenter.default.removeObserver(self)
    }
    
    func updateCompassHeading(notification: NSNotification) {
        guard let heading = notification.object as? CLHeading else {
            fatalError("Not a heading object")
        }
        if heading.magneticHeading < 5 || heading.magneticHeading > 355 {
            headingInRange()
        } else {
            self.numberOfVibrate = 0
            self.withinRange = false
            self.vibrateTimer.invalidate()
        }
        
        degreesLabel.text = String(describing:heading.magneticHeading)
        degreesLabel.sizeToFit()
        degreesLabel.center.x = self.view.center.x
    }
    
    func headingInRange() {
        if self.withinRange {
            //stil in range
            return
        } else {
            self.withinRange = true
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.vibrateTimer  = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(CompassViewController.vibrateAgain)), userInfo: nil, repeats: false)
        }
    }
    
    func vibrateAgain() {
        self.numberOfVibrate += 1
        print(self.numberOfVibrate)
        if self.numberOfVibrate < 5 {
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.vibrateTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(CompassViewController.vibrateAgain)), userInfo: nil, repeats: false)
        } else {
            performSegue(withIdentifier: "ImageCaptureSegue", sender: self)
        }
    }
    

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        guard let imageCaptureViewController = segue.destination as? ImageCaptureViewController else {
            fatalError("Expected ImageCaptureViewController")
        }
        guard let man = self.manager else {
            fatalError("Expected Manager")
        }
        guard let event = self.event else {
            fatalError("Expected Event")
        }
        imageCaptureViewController.manager = man
        imageCaptureViewController.event = event
        man.stopUpdatingCompassHeading()
        self.removeCompassObserver()
    }
}
