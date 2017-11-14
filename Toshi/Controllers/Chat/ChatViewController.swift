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
import MobileCoreServices
import AVFoundation

final class ChatViewController: UIViewController, UINavigationControllerDelegate {
    
    let thread: TSThread
    
    fileprivate var isVisible: Bool = false
    fileprivate lazy var viewModel = ChatViewModel(output: self, thread: self.thread)
    fileprivate lazy var imagesCache: NSCache<NSString, UIImage> = NSCache()

    fileprivate var textInputHeight: CGFloat = ChatInputTextPanel.defaultHeight {
        didSet {
            if isVisible {
                updateContentInset()
                updateConstraints()
            }
        }
    }

    fileprivate var heightOfKeyboard: CGFloat = 0 {
        didSet {
            if isVisible, heightOfKeyboard != oldValue {
                updateContentInset()
                updateConstraints()
            }
        }
    }

    fileprivate lazy var avatarImageView: AvatarImageView = {
        let avatar = AvatarImageView(image: UIImage())
        avatar.bounds.size = CGSize(width: 34, height: 34)
        avatar.set(height: 34.0)
        avatar.set(width: 34.0)
        avatar.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.showContactProfile))
        avatar.addGestureRecognizer(tap)

        return avatar
    }()

    fileprivate lazy var ethereumPromptView: ChatFloatingHeaderView = {
        let view = ChatFloatingHeaderView(withAutoLayout: true)
        view.delegate = self

        return view
    }()

    fileprivate lazy var networkView = defaultActiveNetworkView()
    
    private lazy var buttonsView: ChatButtonsView = {
        let view = ChatButtonsView()
        view.delegate = self
        
        return view
    }()
    
    private(set) lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .plain)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.viewBackgroundColor
        view.estimatedRowHeight = 64.0
        view.scrollsToTop = false
        view.dataSource = self
        view.delegate = self
        view.separatorStyle = .none
        view.keyboardDismissMode = .interactive
        
        if #available(iOS 11.0, *) {
            view.contentInsetAdjustmentBehavior = .never
        }

        view.register(MessagesImageCell.self)
        view.register(MessagesPaymentCell.self)
        view.register(MessagesTextCell.self)

        return view
    }()

    fileprivate lazy var textInputView = ChatInputTextPanel(withAutoLayout: true)
    fileprivate lazy var activityView = self.defaultActivityIndicator()
    
    private var textInputViewBottomConstraint: NSLayoutConstraint?
    private var textInputViewHeightConstraint: NSLayoutConstraint?
    
    init(thread: TSThread) {
        self.thread = thread

        super.init(nibName: nil, bundle: nil)

        hidesBottomBarWhenPushed = true
        title = thread.name()

        NotificationCenter.default.addObserver(self, selector: #selector(handleBalanceUpdate(_:)), name: .ethereumBalanceUpdateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide(_:)), name: .UIKeyboardDidHide, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: .UIKeyboardWillShow, object: nil)
        
        automaticallyAdjustsScrollViewInsets = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateContentInset() {
        let activeNetworkViewHeight = activeNetworkView.heightConstraint?.constant ?? 0
        let topInset = ChatFloatingHeaderView.height + 64.0 + activeNetworkViewHeight
        
        // The tableview is inverted 180 degrees
        tableView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: topInset + 2 + 10, right: 0)
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: topInset + 2, right: 0)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.viewBackgroundColor

        addSubviewsAndConstraints()
        setupActivityIndicator()
        setupActiveNetworkView(hidden: true)
        
        textInputView.delegate = self
        tableView.transform = CGAffineTransform(scaleX: 1, y: -1)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        preferLargeTitleIfPossible(false)

        isVisible = true

        viewModel.loadFirstMessages()

        viewModel.reloadDraft { [weak self] placeholder in
            self?.textInputView.text = placeholder
        }

        tabBarController?.tabBar.isHidden = true

        if let avatarPath = viewModel.contact?.avatarPath {
            AvatarManager.shared.avatar(for: avatarPath, completion: { [weak self] image, _ in
                self?.avatarImageView.image = image
            })
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: avatarImageView)

        updateContentInset()
        updateBalance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        viewModel.markAllMessagesAsRead()
        SignalNotificationManager.updateUnreadMessagesNumber()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isVisible = false
        heightOfKeyboard = 0

        viewModel.saveDraftIfNeeded(inputViewText: textInputView.text)

        viewModel.markAllMessagesAsRead()
        SignalNotificationManager.updateUnreadMessagesNumber()

        preferLargeTitleIfPossible(true)
    }

    fileprivate func updateBalance() {

        viewModel.fetchAndUpdateBalance(cachedCompletion: { [weak self] cachedBalance, _ in
            self?.set(balance: cachedBalance)

        }) { [weak self] fetchedBalance, error in
            if let error = error {
                let alertController = UIAlertController.errorAlert(error as NSError)
                Navigator.presentModally(alertController)
            } else {
                self?.set(balance: fetchedBalance)
            }
        }
    }

    fileprivate func addSubviewsAndConstraints() {
        view.addSubview(tableView)
        view.addSubview(textInputView)
        view.addSubview(buttonsView)
        view.addSubview(ethereumPromptView)

        tableView.top(to: view)
        tableView.left(to: view)
        tableView.right(to: view)

        textInputView.left(to: view)
        textInputViewBottomConstraint = textInputView.bottom(to: view)
        textInputView.right(to: view)
        textInputViewHeightConstraint = textInputView.height(ChatInputTextPanel.defaultHeight)
        
        buttonsView.topToBottom(of: tableView)
        buttonsView.leadingToSuperview()
        buttonsView.bottomToTop(of: textInputView)
        buttonsView.trailingToSuperview()
        
        ethereumPromptView.top(to: view, offset: 64)
        ethereumPromptView.left(to: view)
        ethereumPromptView.right(to: view)
        ethereumPromptView.height(ChatFloatingHeaderView.height)
    }

    func sendPayment(with parameters: [String: Any]) {
        showActivityIndicator()
        viewModel.interactor.sendPayment(with: parameters) { [weak self] success in
            if success {
                self?.updateBalance()
            }
        }
    }

    fileprivate func updateConstraints() {
        textInputViewBottomConstraint?.constant = heightOfKeyboard < -textInputHeight ? heightOfKeyboard + textInputHeight + ChatButtonsView.height : 0
        textInputViewHeightConstraint?.constant = textInputHeight
        
        keyboardAwareInputView.height = ChatButtonsView.height + textInputHeight
        keyboardAwareInputView.invalidateIntrinsicContentSize()

        view.layoutIfNeeded()
    }

    @objc fileprivate func showContactProfile(_ sender: UITapGestureRecognizer) {
        if let contact = self.viewModel.contact, sender.state == .ended {
            let contactController = ProfileViewController(contact: contact)
            navigationController?.pushViewController(contactController, animated: true)
        }
    }

    @objc fileprivate func handleBalanceUpdate(_ notification: Notification) {
        guard notification.name == .ethereumBalanceUpdateNotification, let balance = notification.object as? NSDecimalNumber else { return }
        set(balance: balance)
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        if textInputView.inputField.isFirstResponder() == true {
            scrollToBottom(animated: false)
        }
    }
    
    @objc private func keyboardDidHide(_ notification: Notification) {
        becomeFirstResponder()
    }

    fileprivate func adjustToLastMessage() {
        let buttonsMessage = viewModel.messages.flatMap { $0.sofaWrapper as? SofaMessage }.first(where: { $0.buttons.count > 0 })
        buttonsView.buttons = buttonsMessage?.buttons
    }

    fileprivate func scrollToBottom(animated: Bool = true) {
        guard self.tableView.numberOfRows(inSection: 0) > 0 else { return }

        self.tableView.scrollToRow(at: IndexPath(item: 0, section: 0), at: .bottom, animated: true)
    }

    fileprivate func adjustToPaymentState(_ state: PaymentState, at indexPath: IndexPath) {
        guard let message = self.viewModel.messageModels.element(at: indexPath.row), message.type == .paymentRequest || message.type == .payment, let signalMessage = message.signalMessage else { return }

        signalMessage.paymentState = state
        signalMessage.save()

        (tableView.cellForRow(at: indexPath) as? MessagesPaymentCell)?.setPaymentState(signalMessage.paymentState, paymentStateText: signalMessage.paymentStateText(), for: message.type)

        tableView.beginUpdates()
        tableView.endUpdates()
    }

    fileprivate func image(for message: MessageModel) -> UIImage {
        var image = UIImage()
        if let cachedImage = self.imagesCache.object(forKey: message.identifier as NSString) {
            image = cachedImage
        } else if let messageImage = message.image {
            let maxWidth: CGFloat = UIScreen.main.bounds.width * 0.5

            let maxSize = CGSize(width: maxWidth, height: UIScreen.main.bounds.height)
            let imageFitSize = TGFitSizeF(messageImage.size, maxSize)

            image = ScaleImageToPixelSize(messageImage, imageFitSize)

            imagesCache.setObject(image, forKey: message.identifier as NSString)
        }

        return image
    }

    fileprivate func set(balance: NSDecimalNumber) {
        ethereumPromptView.balance = balance
    }

    // MARK: - Control handling

    fileprivate func didTapControlButton(_ button: SofaMessage.Button) {
        if let action = button.action as? String {
            let prefix = "Webview::"
            guard action.hasPrefix(prefix) else { return }
            guard let actionPath = action.components(separatedBy: prefix).last,
                let url = URL(string: actionPath) else { return }

            let sofaWebController = SOFAWebController()
            sofaWebController.load(url: url)

            navigationController?.pushViewController(sofaWebController, animated: true)
        } else if button.value != nil {
            buttonsView.buttons = nil
            let command = SofaCommand(button: button)
            viewModel.interactor.sendMessage(sofaWrapper: command)
        }
    }
    
    fileprivate func approvePaymentForIndexPath(_ indexPath: IndexPath) {
        guard let message = self.viewModel.messageModels.element(at: indexPath.row) else { return }
        
        adjustToPaymentState(.pendingConfirmation, at: indexPath)
        
        guard let paymentRequest = message.sofaWrapper as? SofaPaymentRequest else { return }
        
        showActivityIndicator()
        
        viewModel.interactor.sendPayment(to: paymentRequest.destinationAddress, in: paymentRequest.value) { [weak self] success in
            let state: PaymentState = success ? .approved : .failed
            self?.adjustToPaymentState(state, at: indexPath)
            DispatchQueue.main.asyncAfter(seconds: 2.0) {
                self?.hideActiveNetworkViewIfNeeded()

                self?.updateBalance()
            }
        }
    }
    
    fileprivate func declinePaymentForIndexPath(_ indexPath: IndexPath) {
        adjustToPaymentState(.rejected, at: indexPath)
        
        DispatchQueue.main.asyncAfter(seconds: 2.0) {
            self.hideActiveNetworkViewIfNeeded()
        }
    }
}

extension ChatViewController: UIImagePickerControllerDelegate {

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {

        picker.dismiss(animated: true, completion: nil)

        guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            return
        }

        viewModel.interactor.sendImage(image)
    }
}

extension ChatViewController: UITableViewDelegate {

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let message = viewModel.messageModels[indexPath.item]
        
        if let signalMessage = message.signalMessage as? TSOutgoingMessage, signalMessage.messageState == .unsent {
            
            let delete = UIAlertAction(title: Localized("messages_sent_error_action_delete"), style: .destructive, handler: { _ in
                self.viewModel.deleteItemAt(indexPath)
            })
            
            let resend = UIAlertAction(title: Localized("messages_sent_error_action_resend"), style: .destructive, handler: { _ in
                self.viewModel.resendItemAt(indexPath)
            })
            
            let cancel = UIAlertAction(title: Localized("cancel_action_title"), style: .cancel)
            
            let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            actionSheet.addAction(resend)
            actionSheet.addAction(delete)
            actionSheet.addAction(cancel)
            
            Navigator.presentModally(actionSheet)
            
        } else if message.type == .image {

            let controller = ImagesViewController(messages: viewModel.messageModels, initialIndexPath: indexPath)
            controller.transitioningDelegate = self
            controller.dismissDelegate = self
            controller.title = title
            Navigator.presentModally(controller)
        }
    }
}

extension ChatViewController: UITableViewDataSource {

    public func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        return viewModel.messageModels.count
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row == self.viewModel.messageModels.count - 1 {
            self.viewModel.updateMessagesRange(from: indexPath)
        }
    }

    public func tableView(_: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let message = viewModel.messageModels[indexPath.item]
        let cell = tableView.dequeueReusableCell(withIdentifier: message.reuseIdentifier, for: indexPath)
        
        if let cell = cell as? MessagesBasicCell {

            if !message.isOutgoing, let avatarPath = self.viewModel.contact?.avatarPath {
                AvatarManager.shared.avatar(for: avatarPath, completion: { image, _ in
                    cell.avatarImageView.image = image
                })
            }

            cell.isOutGoing = message.isOutgoing
            cell.positionType = positionType(for: indexPath)

            updateMessageState(message, in: cell)
        }

        if let cell = cell as? MessagesImageCell, message.type == .image {
            cell.messageImage = message.image
        } else if let cell = cell as? MessagesPaymentCell, (message.type == .payment) || (message.type == .paymentRequest), let signalMessage = message.signalMessage {
            cell.titleLabel.text = message.title
            cell.subtitleLabel.text = message.subtitle
            cell.setPaymentState(signalMessage.paymentState, paymentStateText: signalMessage.paymentStateText(), for: message.type)
            cell.selectionDelegate = self

            let isPaymentOpen = (message.signalMessage?.paymentState ?? .none) == .none
            let isMessageActionable = message.isActionable

            let isOpenPaymentRequest = isMessageActionable && isPaymentOpen
            if isOpenPaymentRequest {
                showActiveNetworkViewIfNeeded()
            }

        } else if let cell = cell as? MessagesTextCell, message.type == .simple {
            cell.messageText = message.text
        }

        cell.transform = self.tableView.transform

        return cell
    }

    private func updateMessageState(_ message: MessageModel, in cell: MessagesBasicCell) {

        // we do ignore SOFA::Payment failure because actual payment always succeeds even if warming SOFA message fails due to f.e. a receiver is logged out
        guard message.type != .payment else { return }

        if let signalMessage = message.signalMessage as? TSOutgoingMessage {
            switch signalMessage.messageState {
            case .attemptingOut, .sent_OBSOLETE, .delivered_OBSOLETE, .sentToService:
                cell.sentState = .sent
            case .unsent:
                cell.sentState = .failed
            }
        }
    }

    private func positionType(for indexPath: IndexPath) -> MessagePositionType {

        guard let currentMessage = viewModel.messageModels.element(at: indexPath.row) else {
            // there are no cells
            return .single
        }

        guard let previousMessage = viewModel.messageModels.element(at: indexPath.row - 1) else {
            guard let nextMessage = viewModel.messageModels.element(at: indexPath.row + 1) else {
                // this is the first and only cell
                return .single
            }

            // this is the first cell of many
            return currentMessage.isOutgoing == nextMessage.isOutgoing ? .bottom : .single
        }

        guard let nextMessage = viewModel.messageModels.element(at: indexPath.row + 1) else {
            // this is the last cell
            return currentMessage.isOutgoing == previousMessage.isOutgoing ? .top : .single
        }

        if currentMessage.isOutgoing != previousMessage.isOutgoing, currentMessage.isOutgoing != nextMessage.isOutgoing {
            // the previous and next messages are not from the same user
            return .single
        } else if currentMessage.isOutgoing == previousMessage.isOutgoing, currentMessage.isOutgoing == nextMessage.isOutgoing {
            // the previous and next messages are from the same user
            return .middle
        } else if currentMessage.isOutgoing == previousMessage.isOutgoing {
            // the previous message is from the same user but the next message is not
            return .top
        } else {
            // the next message is from the same user but the previous message is not
            return .bottom
        }
    }
}

extension MessageModel {

    var reuseIdentifier: String {
        switch type {
        case .simple:
            return MessagesTextCell.reuseIdentifier
        case .image:
            return MessagesImageCell.reuseIdentifier
        case .paymentRequest, .payment:
            return MessagesPaymentCell.reuseIdentifier
        case .status:
            return MessagesStatusCell.reuseIdentifier
        }
    }
}

extension ChatViewController: MessagesPaymentCellDelegate {

    func approvePayment(for cell: MessagesPaymentCell) {
        guard let indexPath = self.tableView.indexPath(for: cell) else { return }
        guard let message = self.viewModel.messageModels.element(at: indexPath.row) else { return }
        
        let messageText: String
        if let fiat = message.fiatValueString, let eth = message.ethereumValueString {
            messageText = String(format: Localized("payment_request_confirmation_warning_message"), fiat, eth, thread.name())
        } else {
            messageText = String(format: Localized("payment_request_confirmation_warning_message_fallback"), thread.name())
        }
        
        let alert = UIAlertController(title: Localized("payment_request_confirmation_warning_title"), message: messageText, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: Localized("cancel_action_title"), style: .default, handler: { _ in
            alert.dismiss(animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: Localized("payment_request_confirmation_warning_action_confirm"), style: .default, handler: { _ in
            alert.dismiss(animated: true, completion: nil)
            self.approvePaymentForIndexPath(indexPath)
        }))
        
        Navigator.presentModally(alert)
    }

    func declinePayment(for cell: MessagesPaymentCell) {
        guard let indexPath = self.tableView.indexPath(for: cell) else { return }

        declinePaymentForIndexPath(indexPath)
    }
}

extension ChatViewController: ImagesViewControllerDismissDelegate {

    func imagesAreDismissed(from indexPath: IndexPath) {
        tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
    }
}

extension ChatViewController: ChatViewModelOutput {

    func didRequireGreetingIfNeeded() {
        self.sendGreetingTriggerIfNeeded()
    }

    func didReload() {
        UIView.performWithoutAnimation {
            self.tableView.reloadData()
        }
    }

    func didRequireKeyboardVisibilityUpdate(_ sofaMessage: SofaMessage) {
        if let showKeyboard = sofaMessage.showKeyboard {
            if showKeyboard == true {
                // A small delay is used here to make the inputField be able to become first responder
                DispatchQueue.main.asyncAfter(seconds: 0.1) {
                    self.textInputView.inputField.becomeFirstResponder()
                }
            } else {
                self.textInputView.inputField.resignFirstResponder()
            }
        }
    }

    func didReceiveLastMessage() {
        self.adjustToLastMessage()
    }

    fileprivate func sendGreetingTriggerIfNeeded() {
        if let contact = self.viewModel.contact, contact.isApp && self.viewModel.messages.isEmpty {
            // If contact is an app, and there are no messages between current user and contact
            // we send the app an empty regular sofa message. This ensures that Signal won't display it,
            // but at the same time, most bots will reply with a greeting.

            let initialRequest = SofaInitialRequest(content: ["values": ["paymentAddress", "language"]])
            let initWrapper = SofaInitialResponse(initialRequest: initialRequest)
            viewModel.interactor.sendMessage(sofaWrapper: initWrapper)
        }
    }
}

extension ChatViewController: ChatInteractorOutput {

    func didCatchError(_ message: String) {
        hideActivityIndicator()

        let alert = UIAlertController.dismissableAlert(title: "Error completing transaction", message: message)
        Navigator.presentModally(alert)
    }

    func didFinishRequest() {
        DispatchQueue.main.async {
            self.hideActivityIndicator()
        }
    }
}

extension ChatViewController: ActivityIndicating {
    var activityIndicator: UIActivityIndicatorView {
        return activityView
    }
}

extension ChatViewController: ChatInputTextPanelDelegate {
    
    func inputTextPanel(_: ChatInputTextPanel, requestSendText text: String) {
        let wrapper = SofaMessage(content: ["body": text])

        viewModel.interactor.sendMessage(sofaWrapper: wrapper)
    }

    func inputTextPanelRequestSendAttachment(_: ChatInputTextPanel) {
        view.layoutIfNeeded()

        view.endEditing(true)

        let pickerTypeAlertController = UIAlertController(title: Localized("image-picker-select-source-title"), message: nil, preferredStyle: .actionSheet)
        let cameraAction = UIAlertAction(title: Localized("image-picker-camera-action-title"), style: .default) { _ in
            self.presentImagePicker(sourceType: .camera)
        }

        let libraryAction = UIAlertAction(title: Localized("image-picker-library-action-title"), style: .default) { _ in
            self.presentImagePicker(sourceType: .photoLibrary)
        }

        let cancelAction = UIAlertAction(title: Localized("cancel_action_title"), style: .cancel, handler: nil)

        pickerTypeAlertController.addAction(cameraAction)
        pickerTypeAlertController.addAction(libraryAction)
        pickerTypeAlertController.addAction(cancelAction)

        present(pickerTypeAlertController, animated: true)
    }

    fileprivate func presentImagePicker(sourceType: UIImagePickerControllerSourceType) {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = sourceType
        imagePicker.delegate = self

        present(imagePicker, animated: true)
    }

    func inputTextPanelDidChangeHeight(_ height: CGFloat) {
        textInputHeight = height
    }
}

extension ChatViewController: ChatFloatingHeaderViewDelegate {

    func messagesFloatingView(_: ChatFloatingHeaderView, didPressRequestButton _: UIButton) {
        
        let paymentController = PaymentController(withPaymentType: .request, continueOption: .send)
        paymentController.delegate = self
        
        let navigationController = PaymentNavigationController(rootViewController: paymentController)
        Navigator.presentModally(navigationController)
    }

    func messagesFloatingView(_: ChatFloatingHeaderView, didPressPayButton _: UIButton) {
        view.layoutIfNeeded()
        textInputView.inputField.resignFirstResponder()

        let paymentController = PaymentController(withPaymentType: .send, continueOption: .send)
        paymentController.delegate = self
        
        let navigationController = PaymentNavigationController(rootViewController: paymentController)
        Navigator.presentModally(navigationController)
    }
}

extension ChatViewController: PaymentControllerDelegate {

    func paymentControllerFinished(with valueInWei: NSDecimalNumber?, for controller: PaymentController) {
        defer { dismiss(animated: true) }
        guard let valueInWei = valueInWei else { return }

        switch controller.paymentType {
        case .request:
            let paymentRequest = SofaPaymentRequest(valueInWei: valueInWei)
            viewModel.interactor.sendMessage(sofaWrapper: paymentRequest)

        case .send:
            showActivityIndicator()
            viewModel.interactor.sendPayment(in: valueInWei, completion: { [weak self] success in
                if success {
                    self?.updateBalance()
                }
            })
        }
    }
}

extension ChatViewController: UIViewControllerTransitioningDelegate {

    func animationController(forPresented presented: UIViewController, presenting _: UIViewController, source _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return presented is ImagesViewController ? ImagesViewControllerTransition(operation: .present) : nil
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return dismissed is ImagesViewController ? ImagesViewControllerTransition(operation: .dismiss) : nil
    }

    func interactionControllerForDismissal(using _: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {

        if let imagesViewController = presentedViewController as? ImagesViewController, let transition = imagesViewController.interactiveTransition {
            return transition
        }

        return nil
    }
}

extension ChatViewController: KeyboardAwareAccessoryViewDelegate {
    func inputView(_: KeyboardAwareInputAccessoryView, shouldUpdatePosition keyboardOriginYDistance: CGFloat) {
        heightOfKeyboard = keyboardOriginYDistance
    }

    override var inputAccessoryView: UIView? {
        keyboardAwareInputView.isUserInteractionEnabled = false
        return keyboardAwareInputView
    }
}

extension ChatViewController: ActiveNetworkDisplaying {

    var activeNetworkView: ActiveNetworkView {
        return networkView
    }

    var activeNetworkViewConstraints: [NSLayoutConstraint] {
        return [activeNetworkView.topAnchor.constraint(equalTo: ethereumPromptView.bottomAnchor, constant: -1),
                activeNetworkView.leftAnchor.constraint(equalTo: view.leftAnchor),
                activeNetworkView.rightAnchor.constraint(equalTo: view.rightAnchor)]
    }

    func requestLayoutUpdate() {

        UIView.animate(withDuration: 0.2) {
            self.updateContentInset()
            self.view.layoutIfNeeded()
        }
    }
}

extension ChatViewController: ChatButtonsSelectionDelegate {
    
    func didSelectButton(at indexPath: IndexPath) {
        guard let button = buttonsView.buttons?.element(at: indexPath.item) else { return }
        
        switch button.type {
        case .button:
            didTapControlButton(button)
        case .group:
            showMenu(for: button, at: indexPath)
        }
    }
    
    private func showMenu(for button: SofaMessage.Button, at indexPath: IndexPath) {
        
        if let cell = buttonsView.collectionView.cellForItem(at: indexPath) {
            presentedViewController?.dismiss(animated: true)
            
            let chatMenuTableViewController = ChatMenuTableViewController(for: cell, in: buttonsView)
            chatMenuTableViewController.delegate = self
            chatMenuTableViewController.buttons = button.subcontrols
            present(chatMenuTableViewController, animated: true)
        }
    }
}

extension ChatViewController: ChatMenuTableViewControllerDelegate {
    
    func didSelectButton(_ button: SofaMessage.Button, at indexPath: IndexPath) {
        didTapControlButton(button)
    }
}
