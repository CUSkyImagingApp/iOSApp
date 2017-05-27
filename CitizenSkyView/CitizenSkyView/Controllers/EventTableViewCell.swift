//
//  EventTableViewCell.swift
//  CitizenSkyView
//
//  Created by Jeremy Rapp on 5/26/17.
//  Copyright © 2017 CET. All rights reserved.
//

import Foundation
import UIKit


class EventTableViewCell: UITableViewCell {
    
    
    //MARK: Properties
    @IBOutlet weak var eventName: UILabel!
    @IBOutlet weak var eventDate: UILabel!
    @IBOutlet weak var eventTime: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        //Initialize code
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        //configure the view for the selected state
    }
}
