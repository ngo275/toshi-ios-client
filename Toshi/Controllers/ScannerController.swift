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
import CameraScanner
import AVKit

class ScannerController: ScannerViewController {

    var isStatusBarHidden = false

    override func viewDidLoad() {
        super.viewDidLoad()

        setupActivityIndicator()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard AVCaptureDevice.authorizationStatus(for: .video) == .denied else { return }
        
        let alert = UIAlertController(title: Localized("no_camera_access_title"), message: Localized("no_camera_access_description"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localized("cancel_action_title"), style: .cancel, handler: { _ in
            self.dismiss(animated: true)
        }))
        alert.addAction(UIAlertAction(title: Localized("settings_action"), style: .default, handler: { _ in
            guard let url = URL(string: UIApplicationOpenSettingsURLString), UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        }))
        
        Navigator.presentModally(alert)
    }

    fileprivate lazy var activityView: UIActivityIndicatorView = {
        self.defaultActivityIndicator()
    }()

    override var prefersStatusBarHidden: Bool {
        return isStatusBarHidden
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .slide
    }

    override func setupToolbarItems() {
        toolbar.setItems([self.cancelItem], animated: true)
    }
}

extension ScannerController: ActivityIndicating {

    var activityIndicator: UIActivityIndicatorView {
        return activityView
    }
}

extension ScannerController: PaymentPresentable {

    func setStatusBarHidden(_: Bool) {
        isStatusBarHidden = true
        setNeedsStatusBarAppearanceUpdate()
    }

    func paymentFailed() {
        startScanning()
        isStatusBarHidden = false
        startScanning()
    }

    func paymentDeclined() {
        isStatusBarHidden = false
        startScanning()
    }

    func paymentApproved(with parameters: [String: Any], userInfo: UserInfo) {
        isStatusBarHidden = false
        guard !userInfo.isLocal else {
            if let tabbarController = self.presentingViewController as? TabBarController {
                tabbarController.openPaymentMessage(to: userInfo.address, parameters: parameters)
            }

            return
        }

        showActivityIndicator()

        EthereumAPIClient.shared.createUnsignedTransaction(parameters: parameters) { [weak self] transaction, error in

            guard let transaction = transaction else {
                self?.hideActivityIndicator()
                self?.presentPaymentError(withErrorMessage: error?.localizedDescription ?? "Something went wrong")
                self?.startScanning()

                return
            }

            let signedTransaction = "0x\(Cereal.shared.signWithWallet(hex: transaction))"

            EthereumAPIClient.shared.sendSignedTransaction(originalTransaction: transaction, transactionSignature: signedTransaction) { [weak self] success, _, message in

                self?.hideActivityIndicator()

                guard success else {
                    self?.presentPaymentError(withErrorMessage: message ?? "Something went wrong")
                    self?.startScanning()
                    return
                }

                self?.presentSuccessAlert { [weak self] _ in
                    self?.startScanning()
                }
            }
        }
    }
}
