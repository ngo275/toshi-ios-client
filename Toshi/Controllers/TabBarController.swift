// Copyright (c) 2017 Token Browser, Inc
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import UIKit
import UserNotifications
import CameraScanner

let TabBarItemTitleOffset: CGFloat = -3.0

open class TabBarController: UITabBarController, OfflineAlertDisplaying {
    let offlineAlertView = defaultOfflineAlertView()

    public enum Tab {
        case browsing
        case messaging
        case scanner
        case favorites
        case me
    }

    let tabBarSelectedIndexKey = "TabBarSelectedIndex"

    public var currentNavigationController: UINavigationController? {
        return selectedViewController as? UINavigationController
    }

    fileprivate var chatAPIClient: ChatAPIClient {
        return ChatAPIClient.shared
    }

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    fileprivate lazy var reachabilityManager: ReachabilityManager = {
        let reachabilityManager = ReachabilityManager()
        reachabilityManager.delegate = self

        return reachabilityManager
    }()

    internal lazy var scannerController: ScannerViewController = {
        let controller = ScannerController(instructions: "Scan QR code", types: [.qrCode])
        controller.delegate = self

        return controller
    }()

    internal lazy var placeholderScannerController: UIViewController = {
        let controller = UIViewController()
        controller.tabBarItem = UITabBarItem(title: Localized("tab_bar_title_scan"), image: #imageLiteral(resourceName: "tab3"), tag: 0)
        controller.tabBarItem.titlePositionAdjustment.vertical = TabBarItemTitleOffset
        
        return controller
    }()

    internal var browseViewController: BrowseNavigationController!
    internal var messagingController: RecentNavigationController!
    internal var favoritesController: FavoritesNavigationController!
    internal var settingsController: SettingsNavigationController!

    public init() {
        super.init(nibName: nil, bundle: nil)

        delegate = self
        reachabilityManager.register()

        setupOfflineAlertView(hidden: true)
    }

    public required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc public func setupControllers() {
        browseViewController = BrowseNavigationController(rootViewController: BrowseViewController())
        favoritesController = FavoritesNavigationController(rootViewController: FavoritesController())

        messagingController = RecentNavigationController(nibName: nil, bundle: nil)
        let recentViewController = RecentViewController()

        if let address = UserDefaults.standard.string(forKey: self.messagingController.selectedThreadAddressKey), let thread = recentViewController.thread(withAddress: address) {
            messagingController.viewControllers = [recentViewController, ChatViewController(thread: thread)]
        } else {
            messagingController.viewControllers = [recentViewController]
        }

        settingsController = SettingsNavigationController(rootViewController: SettingsController())

        viewControllers = [
            self.browseViewController,
            self.messagingController,
            self.placeholderScannerController,
            self.favoritesController,
            self.settingsController
        ]

        view.tintColor = Theme.tintColor
        view.backgroundColor = Theme.viewBackgroundColor

        tabBar.barTintColor = Theme.viewBackgroundColor
        tabBar.unselectedItemTintColor = Theme.unselectedItemTintColor

        let index = UserDefaults.standard.integer(forKey: tabBarSelectedIndexKey)
        selectedIndex = index
    }

    func openPaymentMessage(to address: String, parameters: [String: Any]? = nil) {
        dismiss(animated: false) {

            ChatInteractor.getOrCreateThread(for: address)

            DispatchQueue.main.async {
                self.displayMessage(forAddress: address) { controller in
                    if let chatViewController = controller as? ChatViewController, let parameters = parameters {
                        chatViewController.sendPayment(with: parameters)
                    }
                }
            }
        }
    }

    public func displayMessage(forAddress address: String, completion: ((Any?) -> Void)? = nil) {
        if let index = viewControllers?.index(of: messagingController) {
            selectedIndex = index
        }

        messagingController.openThread(withAddress: address, completion: completion)
    }

    public func openThread(_ thread: TSThread, animated:  Bool = true) {
        messagingController.openThread(thread, animated: animated)
    }

    public func `switch`(to tab: Tab) {
        switch tab {
        case .browsing:
            selectedIndex = 0
        case .messaging:
            selectedIndex = 1
        case .scanner:
            presentScanner()
        case .favorites:
            selectedIndex = 3
        case .me:
            selectedIndex = 4
        }
    }

    fileprivate func presentScanner() {
        SoundPlayer.playSound(type: .menuButton)
        Navigator.presentModally(scannerController)
    }

    @objc public func openDeepLinkURL(_ url: URL) {
        if url.user == "username" {
            guard let username = url.host else { return }

            idAPIClient.retrieveUser(username: username) { [weak self] contact in
                guard let contact = contact else { return }

                let contactController = ProfileViewController(contact: contact)
                (self?.selectedViewController as? UINavigationController)?.pushViewController(contactController, animated: true)
            }
        }
    }
}

extension TabBarController: UITabBarControllerDelegate {

    public func tabBarController(_: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController != browseViewController {
            guard let browseViewController = browseViewController.viewControllers.first as? BrowseViewController else { return true }
            browseViewController.dismissSearchIfNeeded()
        }

        if viewController == placeholderScannerController {
            presentScanner()

            return false
        }

        return true
    }

    public func tabBarController(_: UITabBarController, didSelect viewController: UIViewController) {
        SoundPlayer.playSound(type: .menuButton)

        automaticallyAdjustsScrollViewInsets = viewController.automaticallyAdjustsScrollViewInsets

        if let index = self.viewControllers?.index(of: viewController) {
            UserDefaults.standard.set(index, forKey: tabBarSelectedIndexKey)
        }
    }
}

extension TabBarController: ScannerViewControllerDelegate {

    public func scannerViewControllerDidCancel(_: ScannerViewController) {
        dismiss(animated: true)
    }

    public func scannerViewController(_ controller: ScannerViewController, didScanResult result: String) {
        
        guard reachabilityManager.reachability?.currentReachabilityStatus != .notReachable else {
            let alert = UIAlertController(title: Localized("error-alert-title"), message: Localized("offline_alert_message"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localized("alert-ok-action-title"), style: .cancel, handler: { _ in
                self.scannerController.startScanning()
            }))
            
            Navigator.presentModally(alert)
            
            return
        }
        
        if let intent = QRCodeIntent(result: result) {
            switch intent {
            case .webSignIn(let loginToken):
                idAPIClient.adminLogin(loginToken: loginToken) {[weak self] _, _ in
                    SoundPlayer.playSound(type: .scanned)
                    self?.dismiss(animated: true)
                }
            case .paymentRequest(let weiValue, let address, let username, _):
                if let username = username {
                    proceedToPayment(username: username, weiValue: weiValue)
                } else if let address = address {
                    proceedToPayment(address: address, weiValue: weiValue)
                }
            case .addContact(let username):
                let contactName = TokenUser.name(from: username)
                viewContact(with: contactName)
            default:
                scannerController.startScanning()
            }
        } else {
            scannerController.startScanning()
        }
    }

    private func proceedToPayment(address: String, weiValue: String?) {
        let userInfo = UserInfo(address: address, paymentAddress: address, avatarPath: nil, name: nil, username: address, isLocal: false)
        var parameters = ["from": Cereal.shared.paymentAddress, "to": address]
        parameters["value"] = weiValue

        proceedToPayment(userInfo: userInfo, parameters: parameters)
    }

    private func proceedToPayment(username: String, weiValue: String?) {
        idAPIClient.retrieveUser(username: username) { [weak self] contact in
            if let contact = contact {
                var parameters = ["from": Cereal.shared.paymentAddress, "to": contact.paymentAddress]
                parameters["value"] = weiValue

                self?.proceedToPayment(userInfo: contact.userInfo, parameters: parameters)
            } else {
                self?.scannerController.startScanning()
            }
        }
    }

    private func proceedToPayment(userInfo: UserInfo, parameters: [String: Any]) {
        if parameters["value"] != nil, let scannerController = self.scannerController as? PaymentPresentable {
            scannerController.setStatusBarHidden(true)
            scannerController.displayPaymentConfirmation(userInfo: userInfo, parameters: parameters)
            SoundPlayer.playSound(type: .scanned)
        } else {
            scannerController.startScanning()
        }
    }

    private func viewContact(with contactName: String) {
        idAPIClient.retrieveUser(username: contactName) { [weak self] contact in
            guard let contact = contact else {
                self?.scannerController.startScanning()

                return
            }

            SoundPlayer.playSound(type: .scanned)

            self?.dismiss(animated: true) {
                self?.switch(to: .favorites)
                let contactController = ProfileViewController(contact: contact)
                self?.favoritesController.pushViewController(contactController, animated: true)
            }
        }
    }

}

extension TabBarController: ReachabilityDelegate {
    func reachabilityDidChange(toConnected connected: Bool) {

        if connected {
            hideOfflineAlertView()
        } else {
            showOfflineAlertView()
        }
    }
}
