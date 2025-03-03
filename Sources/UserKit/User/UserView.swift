//
//  UserView.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI

struct UserView: View {
    @ObservedObject var userManager: UserManager
    
    var body: some View {
        if let callManager = userManager.call {
            CallView(callManager: callManager)
        }
    }
}
