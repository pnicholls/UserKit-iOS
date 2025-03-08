//
//  UIViewController+TopViewController.swift
//  UserKit
//
//  Created by Peter Nicholls on 8/3/2025.
//

import Foundation
import UIKit

extension UIApplication {
    var activeWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.flatMap {
            ($0 as? UIWindowScene)?.windows ?? []
        }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }
}
