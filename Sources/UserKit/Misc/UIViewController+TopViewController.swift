//
//  UIViewController+TopViewController.swift
//  UserKit
//
//  Created by Peter Nicholls on 8/3/2025.
//

import UIKit

extension UIViewController {
    static var topViewController: UIViewController? {
        var topViewController: UIViewController? = UIApplication.shared.activeWindow?.rootViewController
        while let presentedViewController = topViewController?.presentedViewController {
            topViewController = presentedViewController
        }
        return topViewController
    }
}
