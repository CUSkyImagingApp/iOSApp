//
//  PermissionsStoryboardSegue.swift
//  CitizenSkyView
//
//  Created by Jeremy Rapp on 5/29/17.
//  Copyright © 2017 CET. All rights reserved.
//

import Foundation
import UIKit


class PermissionsStoryboardSegue : UIStoryboardSegue {
    override func perform(){
        
        let slideView = destination.view
        
        source.view.addSubview(slideView!)
        slideView?.transform = CGAffineTransform(translationX: 0, y: source.view.frame.size.height)
        
        UIView.animate(withDuration: 1,
                       delay: 0.5,
                       options: UIViewAnimationOptions.curveEaseInOut,
                       animations: {
                        slideView?.transform = CGAffineTransform.identity
        }, completion: { finished in
            
            self.source.present(self.destination, animated: false, completion: nil)
            slideView?.removeFromSuperview()
        })
    }
}
