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

class ViewController: UIViewController {
    
    
    //MARK: Properties
    
    

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: Actions
    
    @IBAction func takePicture(_ sender: UIButton){
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                                identityPoolId:"us-west-2:43473766-619f-4209-996b-7dc61e65ccf1")
        let configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
    }

}

