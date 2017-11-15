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
import SweetUIKit
import CoreImage
import TinyConstraints

public class ProfileViewController: UIViewController {

    fileprivate lazy var activityView: UIActivityIndicatorView = {
        self.defaultActivityIndicator()
    }()

    public var contact: TokenUser

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    fileprivate var messageSender: MessageSender? {
        let appDelegate = UIApplication.shared.delegate as? AppDelegate

        return appDelegate?.messageSender
    }

    private var profileView: ProfileView? { return view as? ProfileView }

    public init(contact: TokenUser) {
        self.contact = contact

        super.init(nibName: nil, bundle: nil)

        if #available(iOS 11.0, *) {
            edgesForExtendedLayout = .all
        } else {
            edgesForExtendedLayout = .bottom
        }

        title = "Contact"
    }

    public required init?(coder _: NSCoder) {
        fatalError("The method `init?(coder)` is not implemented for this class.")
    }

    open override func loadView() {
        if contact.isCurrentUser {
            view = ProfileView(viewType: .personalProfileReadOnly)
        } else {
            view = ProfileView(viewType: .profile)
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        setupActivityIndicator()

        profileView?.profileDelegate = self

        if !contact.isCurrentUser {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "more"), style: .plain, target: self, action: #selector(didSelectMoreButton))
        }

        view.backgroundColor = Theme.lightGrayBackgroundColor

        updateReputation()

        NotificationCenter.default.addObserver(self, selector: #selector(yapDatabaseDidChange(notification:)), name: .YapDatabaseModified, object: nil)
    }

    fileprivate lazy var uiDatabaseConnection: YapDatabaseConnection = {
        let database = Yap.sharedInstance.database!
        let dbConnection = database.newConnection()
        dbConnection.beginLongLivedReadTransaction()

        return dbConnection
    }()

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        preferLargeTitleIfPossible(false)

        profileView?.setContact(contact)

        AvatarManager.shared.avatar(for: contact.avatarPath) { [weak self] image, _ in
            if image != nil {
                self?.profileView?.avatarImageView.image = image
            }
        }

        updateButton()
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        preferLargeTitleIfPossible(true)
    }

    @objc
    fileprivate func yapDatabaseDidChange(notification _: NSNotification) {
        let notifications = uiDatabaseConnection.beginLongLivedReadTransaction()

        if uiDatabaseConnection.hasChange(forKey: contact.address, inCollection: TokenUser.favoritesCollectionKey, in: notifications) {
            updateButton()
        }
    }
    
    private func updateButton() {
        uiDatabaseConnection.read { [weak self] transaction in
            guard let strongSelf = self else { return }

            let isContactAdded = transaction.object(forKey: strongSelf.contact.address, inCollection: TokenUser.favoritesCollectionKey) != nil

            let fontColor = isContactAdded ? Theme.tintColor : Theme.lightGreyTextColor
            let title = isContactAdded ? "Favorited" : "Favorite"

            strongSelf.profileView?.actionView.addFavoriteButton.titleLabel.text = title
            strongSelf.profileView?.actionView.addFavoriteButton.tintColor = fontColor
        }
    }

    private func presentUserRatingPrompt(contact: TokenUser) {
        let rateUserController = RateUserController(user: contact)
        rateUserController.delegate = self

        Navigator.presentModally(rateUserController)
    }

    @objc private func didSelectMoreButton() {
        let actions = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let address = contact.address

        if contact.isBlocked {
            let unblockAction = UIAlertAction(title: Localized("unblock_action_title"), style: .destructive) { _ in
                OWSBlockingManager.shared().removeBlockedPhoneNumber(address)

                let alert = UIAlertController.dismissableAlert(title: Localized("unblock_user_title"), message: Localized("unblock_user_message"))
                Navigator.presentModally(alert)
            }

            actions.addAction(unblockAction)
        } else {
            let blockUserAction = UIAlertAction(title: Localized("block_action_title"), style: .destructive) { _ in
                self.didSelectBlockUser()
            }

            actions.addAction(blockUserAction)
        }

        let reportAction = UIAlertAction(title: Localized("report_action_title"), style: .destructive) { _ in
            self.idAPIClient.reportUser(address: address) { success, error in
                self.showReportUserFeedbackAlert(success, message: error?.description)
            }
        }

        actions.addAction(reportAction)
        actions.addAction(UIAlertAction(title: Localized("cancel_action_title"), style: .cancel))

        Navigator.presentModally(actions)
    }

    private func showReportUserFeedbackAlert(_ success: Bool, message: String?) {
        guard success else {
            let alert = UIAlertController.dismissableAlert(title: Localized("error_title"), message: message)
            Navigator.presentModally(alert)

            return
        }

        let alert = UIAlertController.dismissableAlert(title: Localized("report_feedback_alert_title"), message: Localized("report_feedback_alert_message"))
        Navigator.presentModally(alert)
    }

    private func didSelectBlockUser() {
        let alert = UIAlertController(title: Localized("block_alert_title"), message: Localized("block_alert_message"), preferredStyle: .alert)
        let blockAction = UIAlertAction(title: Localized("block_action_title"), style: .default) { _ in
            OWSBlockingManager.shared().addBlockedPhoneNumber(self.contact.address)

            let alert = UIAlertController.dismissableAlert(title: Localized("block_feedback_alert_title"), message: Localized("block_feedback_alert_message"))
            Navigator.presentModally(alert)
        }

        alert.addAction(blockAction)
        alert.addAction(UIAlertAction(title: Localized("cancel_action_title"), style: .cancel))

        Navigator.presentModally(alert)
    }

    fileprivate func updateReputation() {
        RatingsClient.shared.scores(for: contact.address) { [weak self] ratingScore in
            self?.profileView?.reputationView.setScore(ratingScore)
        }
    }
}

extension ProfileViewController: ActivityIndicating {
    var activityIndicator: UIActivityIndicatorView {
        return activityView
    }
}

extension ProfileViewController: RateUserControllerDelegate {
    func didRate(_ user: TokenUser, rating: Int, review: String) {
        dismiss(animated: true) {
            RatingsClient.shared.submit(userId: user.address, rating: rating, review: review) { [weak self] success, error in
                guard success == true else {
                    let alert = UIAlertController(title: "Error", message: error?.description, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))

                    Navigator.presentModally(alert)
                    return
                }

                self?.updateReputation()
            }
        }
    }
}

extension ProfileViewController: PaymentControllerDelegate {

    func paymentControllerFinished(with valueInWei: NSDecimalNumber?, for controller: PaymentController) {
        
        defer { dismiss(animated: true) }
        guard let value = valueInWei else { return }

        let etherAPIClient = EthereumAPIClient.shared

        let parameters: [String: Any] = [
            "from": Cereal.shared.paymentAddress,
            "to": self.contact.paymentAddress,
            "value": value.toHexString
        ]

        showActivityIndicator()

        etherAPIClient.createUnsignedTransaction(parameters: parameters) { [weak self] transaction, error in

            guard let transaction = transaction else {
                self?.hideActivityIndicator()
                let alert = UIAlertController.dismissableAlert(title: "Error completing transaction", message: error?.localizedDescription)
                Navigator.presentModally(alert)

                return
            }

            let signedTransaction = "0x\(Cereal.shared.signWithWallet(hex: transaction))"

            etherAPIClient.sendSignedTransaction(originalTransaction: transaction, transactionSignature: signedTransaction) { [weak self] success, json, error in
                guard let strongSelf = self else { return }

                strongSelf.hideActivityIndicator()

                guard success else {
                    let alert = UIAlertController.dismissableAlert(title: "Error completing transaction", message: error?.description ?? Localized("request_generic_error"))
                    Navigator.presentModally(alert)
                    return
                }

                if let json = json?.dictionary {
                    guard let txHash = json["tx_hash"] as? String else {
                        CrashlyticsLogger.log("Error recovering transaction hash.")
                        fatalError("Error recovering transaction hash.") }
                    let payment = SofaPayment(txHash: txHash, valueHex: value.toHexString)

                    // send message to thread
                    let thread = ChatInteractor.getOrCreateThread(for: strongSelf.contact.address)
                    let timestamp = NSDate.ows_millisecondsSince1970(for: Date())
                    let outgoingMessage = TSOutgoingMessage(timestamp: timestamp, in: thread, messageBody: payment.content)

                    strongSelf.messageSender?.send(outgoingMessage, success: {
                        print("message sent")
                    }, failure: { error in
                        CrashlyticsLogger.log("Can not send message", attributes: [.error: error.localizedDescription])
                        print(error)
                    })
                }
            }
        }
    }
}

extension ProfileViewController: ProfileViewDelegate {
    func didTapMessageContactButton(in view: ProfileView) {
        // create thread if needed
        ChatInteractor.getOrCreateThread(for: contact.address)

        DispatchQueue.main.async {
            (self.tabBarController as? TabBarController)?.displayMessage(forAddress: self.contact.address)

            if let navController = self.navigationController as? BrowseNavigationController {
                _ = navController.popToRootViewController(animated: false)
            }
        }
    }

    func didTapAddContactButton(in view: ProfileView) {
        if Yap.sharedInstance.containsObject(for: contact.address, in: TokenUser.favoritesCollectionKey) {
            Yap.sharedInstance.removeObject(for: contact.address, in: TokenUser.favoritesCollectionKey)
        } else {
            Yap.sharedInstance.insert(object: contact.json, for: contact.address, in: TokenUser.favoritesCollectionKey)
            SoundPlayer.playSound(type: .addedContact)
        }
    }

    func didTapPayButton(in view: ProfileView) {
        let paymentController = PaymentController(withPaymentType: .send, continueOption: .send)
        paymentController.delegate = self

        let navigationController = UINavigationController(rootViewController: paymentController)
        Navigator.presentModally(navigationController)
    }

    func didTapRateUser(in view: ProfileView) {
        presentUserRatingPrompt(contact: contact)
    }
}
