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
import NoChat
import MobileCoreServices
import ImagePicker
import AVFoundation

final class ChatController: OverlayController, ListAdapterDataSource {
    /**
     Asks the data source for a view to use as the collection view background when the list is empty.
     
     @param listAdapter The list adapter requesting this information.
     
     @return A view to use as the collection view background, or `nil` if you don't want a background view.
     
     @note This method is called every time the list adapter is updated. You are free to return new views every time,
     but for performance reasons you may want to retain the view and return it here. The infra is only responsible for
     adding the background view and maintaining its visibility.
     */
    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    /**
     Asks the data source for a section controller for the specified object in the list.
     
     @param listAdapter The list adapter requesting this information.
     @param object An object in the list.
     
     @return A new section controller instance that can be displayed in the list.
     
     @note New section controllers should be initialized here for objects when asked. You may pass any other data to
     the section controller at this time.
     
     Section controllers are initialized for all objects whenever the `IGListAdapter` is created, updated, or reloaded.
     Section controllers are reused when objects are moved or updated. Maintaining the `-[IGListDiffable diffIdentifier]`
     guarantees this.
     */
    func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        let workingRangeSectionController = WorkingRangeSectionController()
        workingRangeSectionController.datasource = self

     //   if let message = object as? MessageModel {
//
//            let index = self.viewModel.messageModels.index(where: { $0.identifier == message.identifier })
            print("Section index:")
//           // guard index != nil else { return workingRangeSectionController }
//
//            //let indexPath = IndexPath(row: index!, section: 0)
//            workingRangeSectionController.positionType = .single //self.positionType(for: indexPath)
//            workingRangeSectionController.avatarPath = self.viewModel.contact?.avatarPath
            //workingRangeSectionController.message = self.viewModel.messageModels.first
     //   }

        return workingRangeSectionController
    }

    /**
     Asks the data source for the objects to display in the list.
     
     @param listAdapter The list adapter requesting this information.
     
     @return An array of objects for the list.
     */
    func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        return self.viewModel.messageModels
    }

    lazy var adapter: ListAdapter = {
        ListAdapter(updater: ListAdapterUpdater(), viewController: self, workingRangeSize:3)
    }()

    //------------------------------------------------------------------------------------------------------------------------------------------------------------
    fileprivate static let subcontrolsViewWidth: CGFloat = 228.0
    fileprivate static let buttonMargin: CGFloat = 10

    private(set) var thread: TSThread

    fileprivate var menuSheetController: MenuSheetController?
    fileprivate var isVisible: Bool = false

    fileprivate lazy var viewModel: ChatViewModel = ChatViewModel(output: self, thread: self.thread)
    fileprivate lazy var imagesCache: NSCache<NSString, UIImage> = NSCache()
    fileprivate lazy var disposable: SMetaDisposable = SMetaDisposable()

    fileprivate var buttons: [SofaMessage.Button] = [] {
        didSet {
            adjustToNewButtons()
        }
    }

    fileprivate var textInputHeight: CGFloat = ChatInputTextPanel.defaultHeight {
        didSet {
            if self.isVisible {
                updateContentInset()
                updateConstraints()
            }
        }
    }

    fileprivate var buttonsHeight: CGFloat = 0 {
        didSet {
            if self.isVisible {
                updateContentInset()
                updateConstraints()
            }
        }
    }

    fileprivate var heightOfKeyboard: CGFloat = 0 {
        didSet {
            if self.isVisible, heightOfKeyboard != oldValue {
                updateContentInset()
                updateConstraints()
            }
        }
    }

    fileprivate lazy var avatarImageView: AvatarImageView = {
        let avatar = AvatarImageView(image: UIImage())
        avatar.bounds.size = CGSize(width: 34, height: 34)
        avatar.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.showContactProfile))
        avatar.addGestureRecognizer(tap)

        return avatar
    }()

    fileprivate lazy var ethereumPromptView: ChatsFloatingHeaderView = {
        let view = ChatsFloatingHeaderView(withAutoLayout: true)
        view.delegate = self

        return view
    }()

    fileprivate lazy var networkView: ActiveNetworkView = {
        self.defaultActiveNetworkView()
    }()
    
    private lazy var layout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.estimatedItemSize = UICollectionViewFlowLayoutAutomaticSize
        
        return layout
    }()

    private(set) lazy var collectionView: UICollectionView = {
        let view = UICollectionView(frame: .zero, collectionViewLayout: self.layout)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.viewBackgroundColor
        view.scrollsToTop = false
        //view.dataSource = self
        //view.delegate = self
        view.keyboardDismissMode = .interactive

        view.register(MessagesImageCell.self)
        view.register(MessagesPaymentCell.self)
        view.register(MessagesTextCell.self)

        return view
    }()

    fileprivate lazy var textInputView: ChatInputTextPanel = ChatInputTextPanel(withAutoLayout: true)
    fileprivate lazy var activityView: UIActivityIndicatorView = self.defaultActivityIndicator()

    fileprivate lazy var controlsView: ControlsCollectionView = {
        let view = ControlsCollectionView()
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.delegate = self.controlsViewDelegateDatasource
        view.dataSource = self.controlsViewDelegateDatasource
        view.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)

        view.register(ControlCell.self)

        return view
    }()

    fileprivate lazy var subcontrolsView: UICollectionView = {
        let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.layer.borderColor = Theme.borderColor.cgColor
        view.layer.borderWidth = Theme.borderHeight
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear

        view.register(SubcontrolCell.self)
        view.delegate = self.subcontrolsViewDelegateDatasource
        view.dataSource = self.subcontrolsViewDelegateDatasource

        return view
    }()

    private var textInputViewBottomConstraint: NSLayoutConstraint?
    private var textInputViewHeightConstraint: NSLayoutConstraint?
    fileprivate var controlsViewHeightConstraint: NSLayoutConstraint?
    fileprivate var subcontrolsViewHeightConstraint: NSLayoutConstraint?

    fileprivate lazy var controlsViewDelegateDatasource: ControlsViewDelegateDataSource = {
        let controlsViewDelegateDatasource = ControlsViewDelegateDataSource()
        controlsViewDelegateDatasource.actionDelegate = self

        return controlsViewDelegateDatasource
    }()

    fileprivate lazy var subcontrolsViewDelegateDatasource: SubcontrolsViewDelegateDataSource = {
        let subcontrolsViewDelegateDatasource = SubcontrolsViewDelegateDataSource()
        subcontrolsViewDelegateDatasource.actionDelegate = self

        return subcontrolsViewDelegateDatasource
    }()

    // MARK: - Init

    init(thread: TSThread) {
        self.thread = thread

        super.init(nibName: nil, bundle: nil)

        hidesBottomBarWhenPushed = true
        title = thread.name()

        registerNotifications()
    }

    required init?(coder _: NSCoder) {
        fatalError()
    }

    func updateContentInset() {
        let activeNetworkViewHeight = activeNetworkView.heightConstraint?.constant ?? 0
        let topInset = ChatsFloatingHeaderView.height + 64.0 + activeNetworkViewHeight
        let bottomInset = textInputHeight

        // The collectionView is inverted 180 degrees
        // 10 + 2 hmm....?
        collectionView.contentInset = UIEdgeInsets(top: bottomInset + buttonsHeight + 10, left: 0, bottom: topInset + 2 + 10, right: 0)
        collectionView.scrollIndicatorInsets = UIEdgeInsets(top: bottomInset + buttonsHeight, left: 0, bottom: topInset + 2, right: 0)
    }

    fileprivate func registerNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(self.handleBalanceUpdate(notification:)), name: .ethereumBalanceUpdateNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardDidHide), name: .UIKeyboardDidHide, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillShow), name: .UIKeyboardWillShow, object: nil)
    }

    // MARK: View life-cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.viewBackgroundColor

        addSubviewsAndConstraints()

        adapter.collectionView = collectionView
        adapter.dataSource = self

        textInputView.delegate = self

        collectionView.transform = CGAffineTransform (scaleX: 1, y: -1)

        controlsViewDelegateDatasource.controlsCollectionView = controlsView
        subcontrolsViewDelegateDatasource.subcontrolsCollectionView = subcontrolsView

        hideSubcontrolsMenu()
        setupActivityIndicator()
        setupActiveNetworkView(hidden: true)

        viewModel.fetchAndUpdateBalance { [weak self] balance, error in
            if let error = error {
                let alertController = UIAlertController.errorAlert(error as NSError)
                Navigator.presentModally(alertController)
            } else {
                self?.set(balance: balance)
            }
        }
    }

//    override func viewDidLayoutSubviews() {
//        super.viewDidLayoutSubviews()
//        collectionView.frame = view.bounds
//    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        isVisible = true

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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        viewModel.thread.markAllAsRead()
        SignalNotificationManager.updateApplicationBadgeNumber()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isVisible = false
        heightOfKeyboard = 0

        viewModel.saveDraftIfNeeded(inputViewText: textInputView.text)

        viewModel.thread.markAllAsRead()
        SignalNotificationManager.updateApplicationBadgeNumber()
    }

    fileprivate func addSubviewsAndConstraints() {
        view.addSubview(collectionView)
        view.addSubview(textInputView)
        view.addSubview(controlsView)
        view.addSubview(subcontrolsView)
        view.addSubview(ethereumPromptView)

        collectionView.top(to: view)
        collectionView.left(to: view)
        collectionView.bottom(to: textInputView)
        collectionView.right(to: view)

        textInputView.left(to: view)
        textInputViewBottomConstraint = textInputView.bottom(to: view)
        textInputView.right(to: view)
        textInputViewHeightConstraint = textInputView.height(ChatInputTextPanel.defaultHeight)

        controlsView.left(to: view, offset: 16)
        controlsView.bottomToTop(of: textInputView)
        controlsView.right(to: view, offset: -16)
        controlsViewHeightConstraint = controlsView.height(0)

        subcontrolsView.left(to: view, offset: 16)
        subcontrolsView.bottomToTop(of: controlsView)
        subcontrolsView.width(ChatController.subcontrolsViewWidth)
        subcontrolsViewHeightConstraint = subcontrolsView.height(0)

        ethereumPromptView.top(to: view, offset: 64)
        ethereumPromptView.left(to: view)
        ethereumPromptView.right(to: view)
        ethereumPromptView.height(ChatsFloatingHeaderView.height)
    }

    func sendPayment(with parameters: [String: Any]) {
        showActivityIndicator()
        viewModel.interactor.sendPayment(with: parameters)
    }

    func keyboardWillShow() {
        if textInputView.inputField.isFirstResponder() == true {
            scrollToBottom(animated: false)
        }
    }

    func keyboardDidHide() {
        becomeFirstResponder()
    }

    fileprivate func updateConstraints() {
        textInputViewBottomConstraint?.constant = heightOfKeyboard < -textInputHeight ? heightOfKeyboard + textInputHeight + buttonsHeight : 0
        textInputViewHeightConstraint?.constant = textInputHeight

        controlsViewHeightConstraint?.constant = buttonsHeight
        keyboardAwareInputView.height = buttonsHeight + textInputHeight
        keyboardAwareInputView.invalidateIntrinsicContentSize()

        view.layoutIfNeeded()
    }

    @objc
    fileprivate func showContactProfile(_ sender: UITapGestureRecognizer) {
        if let contact = self.viewModel.contact as TokenUser?, sender.state == .ended {
            let contactController = ContactController(contact: contact)
            navigationController?.pushViewController(contactController, animated: true)
        }
    }

    @objc
    fileprivate func handleBalanceUpdate(notification: Notification) {
        guard notification.name == .ethereumBalanceUpdateNotification, let balance = notification.object as? NSDecimalNumber else { return }
        set(balance: balance)
    }

    fileprivate func adjustToNewButtons() {
            self.controlsView.isHidden = true
            self.updateSubcontrols(with: nil)
            self.controlsViewHeightConstraint?.constant = !self.buttons.isEmpty ? 250 : 0
            self.controlsViewDelegateDatasource.items = self.buttons
            self.controlsView.reloadData()

            let duration = !self.buttons.isEmpty ? 0.0 : 0.3

            UIView.animate(withDuration: duration, delay: 0.0, options: [.curveEaseIn, .beginFromCurrentState], animations: {
                self.controlsView.layoutIfNeeded()
            }) { _ in
            }

            var height: CGFloat = 0

            let controlCells = self.controlsView.visibleCells.flatMap { cell in cell as? ControlCell }

            for controlCell in controlCells {
                height = max(height, controlCell.frame.maxY)
            }

            self.controlsViewHeightConstraint?.constant = 0
            UIView.animate(withDuration: 0, delay: 0, animations: {
                self.controlsView.layoutIfNeeded()
            }, completion: { completed in

                if completed {
                    self.controlsView.isHidden = false

                    self.buttonsHeight = height > 0 ? height + (2 * ChatController.buttonMargin) : 0

                    guard height > 0 else { return }
                    self.controlsViewHeightConstraint?.constant = height + (2 * ChatController.buttonMargin)

                    UIView.animate(withDuration: 0.5, delay: 0.5, options: [.curveEaseIn, .beginFromCurrentState], animations: {
                        self.controlsView.layoutIfNeeded()
                    }) { completed in
                        if completed {
                            //self.scrollToBottom()
                        }
                    }

                    self.controlsView.deselectButtons()
                }
            })
    }

    fileprivate func adjustToLastMessage() {
        guard let message = viewModel.messages.first as Message?, let sofaMessage = message.sofaWrapper as? SofaMessage, sofaMessage.buttons.count > 0 else { return }

        self.buttons = sofaMessage.buttons
    }

    fileprivate func scrollToBottom(animated: Bool = true) {
        guard adapter.objects().count > 0 else { return } // collectionView.numberOfItems(inSection: 0) as Int?, numbers > 0 else { return }

        let contentSizeHeight = collectionView.contentSize.height - collectionView.bounds.height
        collectionView.setContentOffset(CGPoint(x: 0, y: contentSizeHeight), animated: false)

        collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .bottom, animated: true)
    }

    fileprivate func adjustToPaymentState(_ state: TSInteraction.PaymentState, at indexPath: IndexPath) {
        guard let message = self.viewModel.messageModels[indexPath.item] as MessageModel?, message.type == .paymentRequest || message.type == .payment, let signalMessage = message.signalMessage as TSMessage? else { return }

        signalMessage.paymentState = state
        signalMessage.save()

        (collectionView.cellForItem(at: indexPath) as? MessagesPaymentCell)?.setPaymentState(signalMessage.paymentState, for: message.type)
        
        collectionView.performBatchUpdates({
            // Calling this even when it's empty should animate the changes.
        }, completion: nil)
    }

    fileprivate func image(for message: MessageModel) -> UIImage {
        var image = UIImage()
        if let cachedImage = self.imagesCache.object(forKey: message.identifier as NSString) as UIImage? {
            image = cachedImage
        } else if let messageImage = message.image as UIImage? {
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
            buttons = []
            let command = SofaCommand(button: button)
            controlsViewDelegateDatasource.controlsCollectionView?.isUserInteractionEnabled = false
            viewModel.interactor.sendMessage(sofaWrapper: command)
        }
    }

    // MARK: - Camera and picker
    fileprivate func displayCamera(from cameraView: AttachmentCameraView?, menu: MenuSheetController, carouselItem _: AttachmentCarouselItemView) {
        var controller: CameraController
        let screenSize = TGScreenSize()

        if let previewView = cameraView?.previewView() as CameraPreviewView? {
            controller = CameraController(camera: previewView.camera, previewView: previewView, intent: CameraControllerGenericIntent)!
        } else {
            controller = CameraController()
        }

        controller.isImportant = true
        controller.shouldStoreCapturedAssets = true
        controller.allowCaptions = true

        let controllerWindow = CameraControllerWindow(parentController: self, contentController: controller)
        controllerWindow?.isHidden = false

        controllerWindow?.frame = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)

        var startFrame = CGRect(x: 0, y: screenSize.height, width: screenSize.width, height: screenSize.height)

        if let cameraView = cameraView as AttachmentCameraView?, let frame = cameraView.previewView().frame as CGRect? {
            startFrame = controller.view.convert(frame, from: cameraView)
        }

        cameraView?.detachPreviewView()
        controller.beginTransitionIn(from: startFrame)

        controller.beginTransitionOut = {

            if let cameraView = cameraView as AttachmentCameraView? {

                cameraView.willAttachPreviewView()
                return controller.view.convert(cameraView.frame, from: cameraView.superview)
            }

            return CGRect.zero
        }

        controller.finishedTransitionOut = {
            cameraView?.attachPreviewView(animated: true)
        }

        controller.finishedWithPhoto = { [weak self] resultImage, _, _ in

            menu.dismiss(animated: true)
            if let image = resultImage as UIImage? {
                self?.viewModel.interactor.send(image: image)
            }
        }

        controller.finishedWithVideo = { [weak self] videoURL, _, _, _, _, _, _ in
            defer { menu.dismiss(animated: false) }

            self?.showActivityIndicator()

            guard let videoURL = videoURL else { return }
            self?.viewModel.interactor.sendVideo(with: videoURL)
        }
    }

    fileprivate func checkMicrophoneAccess() {
        if AVAudioSession.sharedInstance().recordPermission().contains(.undetermined) {

            AVAudioSession.sharedInstance().requestRecordPermission { _ in
            }
        }
    }

    fileprivate func displayMediaPicker(forFile _: Bool, fromFileMenu _: Bool) {

        guard AccessChecker.checkPhotoAuthorizationStatus(intent: PhotoAccessIntentRead, alertDismissCompletion: nil) else { return }
        guard let dismissBlock = { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        } as? () -> Void else { return }

        let showMediaPickerBlock: ((MediaAssetGroup?) -> Void) = { [weak self] group in
            let intent: MediaAssetsControllerIntent = .sendMedia
            let assetsController = MediaAssetsController(assetGroup: group, intent: intent)!
            assetsController.captionsEnabled = true
            assetsController.inhibitDocumentCaptions = true
            assetsController.suggestionContext = SuggestionContext()
            assetsController.dismissalBlock = dismissBlock
            assetsController.localMediaCacheEnabled = false
            assetsController.shouldStoreAssets = false
            assetsController.shouldShowFileTipIfNeeded = false

            assetsController.completionBlock = { signals in

                assetsController.dismiss(animated: true, completion: nil)

                if let signals = signals as? [SSignal] {
                    self?.viewModel.interactor.asyncProcess(signals: signals)
                }
            }

            Navigator.presentModally(assetsController)
        }

        if MediaAssetsLibrary.authorizationStatus() == MediaLibraryAuthorizationStatusNotDetermined {
            MediaAssetsLibrary.requestAuthorization(for: MediaAssetAnyType) { (_, cameraRollGroup) -> Void in

                let photoAllowed = AccessChecker.checkPhotoAuthorizationStatus(intent: PhotoAccessIntentRead, alertDismissCompletion: nil)
                let microphoneAllowed = AccessChecker.checkMicrophoneAuthorizationStatus(for: MicrophoneAccessIntentVideo, alertDismissCompletion: nil)

                if photoAllowed == false || microphoneAllowed == false {
                    return
                }

                showMediaPickerBlock(cameraRollGroup)
            }
        }

        showMediaPickerBlock(nil)
    }
    
    fileprivate func approvePaymentForIndexPath(_ indexPath: IndexPath) {
        guard let message = self.viewModel.messageModels.element(at: indexPath.row) as MessageModel? else { return }
        
        adjustToPaymentState(.pendingConfirmation, at: indexPath)
        
        guard let paymentRequest = message.sofaWrapper as? SofaPaymentRequest else { return }
        
        showActivityIndicator()
        
        viewModel.interactor.sendPayment(in: paymentRequest.value) { [weak self] (success: Bool) in
            let state: TSInteraction.PaymentState = success ? .approved : .failed
            self?.adjustToPaymentState(state, at: indexPath)
            DispatchQueue.main.asyncAfter(seconds: 2.0) {
                self?.hideActiveNetworkViewIfNeeded()
            }
        }
    }
    
    fileprivate func declinePaymentForIndexPath(_ indexPath: IndexPath) {
        adjustToPaymentState(.rejected, at: indexPath)
        
        DispatchQueue.main.asyncAfter(seconds: 2.0) {
            self.hideActiveNetworkViewIfNeeded()
        }
    }

    private func positionType(for indexPath: IndexPath) -> MessagePositionType {

        guard let currentMessage = viewModel.messageModels.element(at: indexPath.item) else {
            // there are no cells
            return .single
        }

        guard let previousMessage = viewModel.messageModels.element(at: indexPath.item - 1) else {
            guard let nextMessage = viewModel.messageModels.element(at: indexPath.item + 1) else {
                // this is the first and only cell
                return .single
            }

            // this is the first cell of many
            return currentMessage.isOutgoing == nextMessage.isOutgoing ? .top : .single
        }

        guard let nextMessage = viewModel.messageModels.element(at: indexPath.item + 1) else {
            // this is the last cell
            return currentMessage.isOutgoing == previousMessage.isOutgoing ? .bottom : .single
        }

        if currentMessage.isOutgoing != previousMessage.isOutgoing, currentMessage.isOutgoing != nextMessage.isOutgoing {
            // the previous and next messages are not from the same user
            return .single
        } else if currentMessage.isOutgoing == previousMessage.isOutgoing, currentMessage.isOutgoing == nextMessage.isOutgoing {
            // the previous and next messages are from the same user
            return .middle
        } else if currentMessage.isOutgoing == previousMessage.isOutgoing {
            // the previous message is from the same user but the next message is not
            return .bottom
        } else {
            // the next message is from the same user but the previous message is not
            return .top
        }
    }
}

//extension ChatController: UITableViewDelegate {
//
//    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
//
//        if viewModel.messageModels[indexPath.row].type == .image {
//
//            let controller = ImagesViewController(messages: viewModel.messageModels, initialIndexPath: indexPath)
//            controller.transitioningDelegate = self
//            controller.dismissDelegate = self
//            controller.title = title
//            Navigator.presentModally(controller)
//        }
//    }
//}

//extension ChatController: UITableViewDataSource {
//
//    public func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
//        guard let messages = self.viewModel.messageModels as [MessageModel]? else { return 0 }
//
//        return messages.count
//    }
//
//    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
//        if indexPath.row == self.viewModel.messageModels.count - 1 {
//            self.viewModel.updateMessagesRange(from: indexPath)
//        }
//    }
//
//    public func tableView(_: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
//
//        let message = viewModel.messageModels[indexPath.item]
//        let cell = tableView.dequeueReusableCell(withIdentifier: message.reuseIdentifier, for: indexPath)
//
//        if let cell = cell as? MessagesBasicCell {
//
//            if !message.isOutgoing, let avatarPath = self.viewModel.contact?.avatarPath as String? {
//                AvatarManager.shared.avatar(for: avatarPath, completion: { image, _ in
//                    cell.avatarImageView.image = image
//                })
//            }
//
//            cell.isOutGoing = message.isOutgoing
//            cell.positionType = positionType(for: indexPath)
//        }
//
//        if let cell = cell as? MessagesImageCell, message.type == .image {
//            cell.messageImage = message.image
//        } else if let cell = cell as? MessagesPaymentCell, (message.type == .payment) || (message.type == .paymentRequest), let signalMessage = message.signalMessage {
//            cell.titleLabel.text = message.title
//            cell.subtitleLabel.text = message.subtitle
//            cell.messageLabel.text = message.text
//            cell.setPaymentState(signalMessage.paymentState, for: message.type)
//            cell.selectionDelegate = self
//
//            let isPaymentOpen = (message.signalMessage?.paymentState ?? .none) == .none
//            let isMessageActionable = message.isActionable
//
//            let isOpenPaymentRequest = isMessageActionable && isPaymentOpen
//            if isOpenPaymentRequest {
//                showActiveNetworkViewIfNeeded()
//            }
//
//        } else if let cell = cell as? MessagesTextCell, message.type == .simple {
//            cell.messageText = message.text
//        }
//
//        cell.transform = self.tableView.transform
//
//        return cell
//    }


//}

extension ChatController:  WorkingRangeDataSource {

    func messagePosition(for index: Int) -> MessagePositionType {
        return .single
    }

    func didPrepareCell(for message: MessageModel) {
        guard let index = viewModel.messageModels.index(of: message) as Int?, index != NSNotFound else { return }

        if index == self.viewModel.messageModels.count - 1 {
            self.viewModel.updateMessagesRange()
        }
    }
}

extension ChatController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        if viewModel.messageModels[indexPath.item].type == .image {

            let controller = ImagesViewController(messages: viewModel.messageModels, initialIndexPath: indexPath)
            controller.transitioningDelegate = self
            controller.dismissDelegate = self
            controller.title = title
            Navigator.presentModally(controller)
        }
    }
}

//extension ChatController: UICollectionViewDataSource {
    
//    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
//        guard let messages = self.viewModel.messageModels as [MessageModel]? else { return 0 }
//
//        return messages.count
//    }
//    
//    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
//        if indexPath.item == self.viewModel.messageModels.count - 1 {
//            self.viewModel.updateMessagesRange(from: indexPath)
//        }
//    }
//    
//    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
//        let message = viewModel.messageModels[indexPath.item]
//        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: message.reuseIdentifier, for: indexPath)
//
//        if let cell = cell as? MessagesBasicCell {
//
//            if !message.isOutgoing, let avatarPath = self.viewModel.contact?.avatarPath as String? {
//                AvatarManager.shared.avatar(for: avatarPath, completion: { image, _ in
//                    cell.avatarImageView.image = image
//                })
//            }
//
//            cell.isOutGoing = message.isOutgoing
//            cell.positionType = positionType(for: indexPath)
//        }
//
//        if let cell = cell as? MessagesImageCell, message.type == .image {
//            cell.messageImage = message.image
//        } else if let cell = cell as? MessagesPaymentCell, (message.type == .payment) || (message.type == .paymentRequest), let signalMessage = message.signalMessage {
//            cell.titleLabel.text = message.title
//            cell.subtitleLabel.text = message.subtitle
//            cell.messageLabel.text = message.text
//            cell.setPaymentState(signalMessage.paymentState, for: message.type)
//            cell.selectionDelegate = self
//
//            let isPaymentOpen = (message.signalMessage?.paymentState ?? .none) == .none
//            let isMessageActionable = message.isActionable
//
//            let isOpenPaymentRequest = isMessageActionable && isPaymentOpen
//            if isOpenPaymentRequest {
//                showActiveNetworkViewIfNeeded()
//            }
//
//        } else if let cell = cell as? MessagesTextCell, message.type == .simple {
//            cell.messageText = message.text
//        }
//
//        return cell
//    }


//}

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

extension ChatController: MessagesPaymentCellDelegate {

    func approvePayment(for cell: MessagesPaymentCell) {
        guard let indexPath = self.collectionView.indexPath(for: cell) as IndexPath? else { return }
        guard let message = self.viewModel.messageModels.element(at: indexPath.row) as MessageModel? else { return }

        let messageText: String
        if let fiat = message.fiatValueString, let eth = message.ethereumValueString {
            messageText = String(format: Localized("payment_request_confirmation_warning_message"), fiat, eth, thread.name())
        } else {
            messageText = String(format: Localized("payment_request_confirmation_warning_message_fallback"), thread.name())

        }

        let alert = UIAlertController(title: Localized("payment_request_confirmation_warning_title"), message: messageText, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localized("payment_request_confirmation_warning_action_cancel"), style: .default, handler: { _ in
            alert.dismiss(animated: true, completion: nil)
        }))

        alert.addAction(UIAlertAction(title: Localized("payment_request_confirmation_warning_action_confirm"), style: .default, handler: { _ in
            alert.dismiss(animated: true, completion: nil)
            self.approvePaymentForIndexPath(indexPath)
        }))

        Navigator.presentModally(alert)
    }

    func declinePayment(for cell: MessagesPaymentCell) {
        guard let indexPath = collectionView.indexPath(for: cell) as IndexPath? else { return }

        declinePaymentForIndexPath(indexPath)
    }
}

extension ChatController: ImagesViewControllerDismissDelegate {

    func imagesAreDismissed(from indexPath: IndexPath) {
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
    }
}

extension ChatController: ChatViewModelOutput {
    func didReload() {
        self.sendGreetingTriggerIfNeeded()

        print("\n\n Did reload - performing updates")
        self.adapter.performUpdates(animated: false)
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

        //self.adapter.performUpdates(animated: false)
    }

    fileprivate func sendGreetingTriggerIfNeeded() {
        if let contact = self.viewModel.contact as TokenUser?, contact.isApp && self.viewModel.messages.isEmpty {
            // If contact is an app, and there are no messages between current user and contact
            // we send the app an empty regular sofa message. This ensures that Signal won't display it,
            // but at the same time, most bots will reply with a greeting.

            let initialRequest = SofaInitialRequest(content: ["values": ["paymentAddress", "language"]])
            let initWrapper = SofaInitialResponse(initialRequest: initialRequest)
            viewModel.interactor.sendMessage(sofaWrapper: initWrapper)
        }
    }
}

extension ChatController: ChatInteractorOutput {

    func didCatchError(_ error: Error) {
        hideActivityIndicator()

        let alert = UIAlertController.dismissableAlert(title: "Error completing transaction", message: error.localizedDescription)
        Navigator.presentModally(alert)
    }

    func didFinishRequest() {
        DispatchQueue.main.async {
            self.hideActivityIndicator()
        }
    }
}

extension ChatController: ActivityIndicating {
    var activityIndicator: UIActivityIndicatorView {
        return activityView
    }
}

extension ChatController: ChatInputTextPanelDelegate {
    func inputPanel(_: NOCChatInputPanel, willChangeHeight _: CGFloat, duration _: TimeInterval, animationCurve _: Int32) {
    }

    func inputTextPanel(_: ChatInputTextPanel, requestSendText text: String) {
        let wrapper = SofaMessage(content: ["body": text])

        viewModel.interactor.sendMessage(sofaWrapper: wrapper)
    }

    func inputTextPanelRequestSendAttachment(_: ChatInputTextPanel) {
        view.layoutIfNeeded()

        view.endEditing(true)

        menuSheetController = MenuSheetController()
        menuSheetController?.dismissesByOutsideTap = true
        menuSheetController?.hasSwipeGesture = true
        menuSheetController?.maxHeight = 445 - MenuSheetButtonItemViewHeight
        var itemViews = [UIView]()

        checkMicrophoneAccess()

        let carouselItem = AttachmentCarouselItemView(camera: Camera.cameraAvailable(), selfPortrait: false, forProfilePhoto: false, assetType: MediaAssetAnyType)!
        carouselItem.condensed = false
        carouselItem.parentController = self
        carouselItem.allowCaptions = true
        carouselItem.inhibitDocumentCaptions = true
        carouselItem.suggestionContext = SuggestionContext()
        carouselItem.cameraPressed = { [weak self] cameraView in
            guard AccessChecker.checkCameraAuthorizationStatus(alertDismissComlpetion: nil) == true else { return }
            guard let strongSelf = self else { return }

            strongSelf.displayCamera(from: cameraView, menu: strongSelf.menuSheetController!, carouselItem: carouselItem)
        }

        carouselItem.sendPressed = { [weak self] currentItem, asFiles in
            self?.menuSheetController?.dismiss(animated: true, manual: false) {

                let intent: MediaAssetsControllerIntent = asFiles == true ? .sendFile : .sendMedia

                if let signals = MediaAssetsController.resultSignals(selectionContext: carouselItem.selectionContext, editingContext: carouselItem.editingContext, intent: intent, currentItem: currentItem, storeAssets: true, useMediaCache: true) as? [SSignal] {
                    self?.viewModel.interactor.asyncProcess(signals: signals)
                }
            }
        }

        itemViews.append(carouselItem)

        let galleryItem = MenuSheetButtonItemView(title: "Photo or Video", type: MenuSheetButtonTypeDefault, action: { [weak self] in

            self?.menuSheetController?.dismiss(animated: true)
            self?.displayMediaPicker(forFile: false, fromFileMenu: false)
        })!

        itemViews.append(galleryItem)

        carouselItem.underlyingViews = [galleryItem]

        let cancelItem = MenuSheetButtonItemView(title: "Cancel", type: MenuSheetButtonTypeCancel, action: {
            self.menuSheetController?.dismiss(animated: true)
        })!

        itemViews.append(cancelItem)
        menuSheetController?.setItemViews(itemViews)
        carouselItem.remainingHeight = MenuSheetButtonItemViewHeight * CGFloat(itemViews.count - 1)

        menuSheetController?.present(in: self, sourceView: view, animated: true)
    }

    func inputTextPanelDidChangeHeight(_ height: CGFloat) {
        textInputHeight = height
    }
}

extension ChatController: ImagePickerDelegate {
    func cancelButtonDidPress(_: ImagePickerController) {
        dismiss(animated: true)
    }

    func doneButtonDidPress(_: ImagePickerController, images: [UIImage]) {
        dismiss(animated: true) {
            for image in images {
                self.viewModel.interactor.send(image: image)
            }
        }
    }

    func wrapperDidPress(_: ImagePickerController, images _: [UIImage]) {
    }
}

extension ChatController: ChatsFloatingHeaderViewDelegate {

    func messagesFloatingView(_: ChatsFloatingHeaderView, didPressRequestButton _: UIButton) {
        
        let paymentController = PaymentController(withPaymentType: .request, continueOption: .next)
        paymentController.delegate = self
        
        let navigationController = PaymentNavigationController(rootViewController: paymentController)
        Navigator.presentModally(navigationController)
    }

    func messagesFloatingView(_: ChatsFloatingHeaderView, didPressPayButton _: UIButton) {
        view.layoutIfNeeded()
        controlsViewHeightConstraint?.constant = 0.0
        textInputView.inputField.resignFirstResponder()

        let paymentController = PaymentController(withPaymentType: .send, continueOption: .send)
        paymentController.delegate = self
        
        let navigationController = PaymentNavigationController(rootViewController: paymentController)
        Navigator.presentModally(navigationController)
    }
}

extension ChatController: PaymentControllerDelegate {

    func paymentControllerFinished(with valueInWei: NSDecimalNumber?, for controller: PaymentController) {
        defer { dismiss(animated: true) }
        guard let valueInWei = valueInWei else { return }

        switch controller.paymentType {
        case .request:
            let request: [String: Any] = [
                "body": "Request for \(EthereumConverter.balanceAttributedString(forWei: valueInWei, exchangeRate: ExchangeRateClient.exchangeRate).string).",
                "value": valueInWei.toHexString,
                "destinationAddress": Cereal.shared.paymentAddress
            ]

            let paymentRequest = SofaPaymentRequest(content: request)

            viewModel.interactor.sendMessage(sofaWrapper: paymentRequest)

        case .send:
            showActivityIndicator()
            viewModel.interactor.sendPayment(in: valueInWei)
        }
    }
}

extension ChatController: UIViewControllerTransitioningDelegate {

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

extension ChatController: KeyboardAwareAccessoryViewDelegate {
    func inputView(_: KeyboardAwareInputAccessoryView, shouldUpdatePosition keyboardOriginYDistance: CGFloat) {
        heightOfKeyboard = keyboardOriginYDistance
    }

    override var inputAccessoryView: UIView? {
        keyboardAwareInputView.isUserInteractionEnabled = false
        return keyboardAwareInputView
    }
}

extension ChatController: ControlViewActionDelegate {

    func controlsCollectionViewDidSelectControl(_ button: SofaMessage.Button) {
        switch button.type {
        case .button:
            didTapControlButton(button)
        case .group:
            updateSubcontrols(with: button)
        }
    }

    func updateSubcontrols(with button: SofaMessage.Button?) {
        switch viewModel.displayState(for: button) {
        case .show:
            showSubcontrolsMenu(button: button!)
        case .hide:
            hideSubcontrolsMenu()
        case .hideAndShow:
            hideSubcontrolsMenu {
                self.showSubcontrolsMenu(button: button!)
            }
        case .doNothing:
            break
        }
    }

    func hideSubcontrolsMenu(completion: (() -> Void)? = nil) {
        subcontrolsViewDelegateDatasource.items = []
        viewModel.currentButton = nil

        subcontrolsViewHeightConstraint?.constant = 0
        subcontrolsView.backgroundColor = .clear
        subcontrolsView.isHidden = true

        controlsView.deselectButtons()

        view.layoutIfNeeded()

        completion?()
    }

    func showSubcontrolsMenu(button: SofaMessage.Button, completion: (() -> Void)? = nil) {
        controlsView.deselectButtons()
        subcontrolsViewHeightConstraint?.constant = view.frame.height
        subcontrolsView.isHidden = true

        let controlCell = SubcontrolCell(frame: .zero)
        var maxWidth: CGFloat = 0.0

        button.subcontrols.forEach { button in
            controlCell.button.setTitle(button.label, for: .normal)
            let bounds = CGRect(x: 0, y: 0, width: self.view.frame.width, height: 38)
            maxWidth = max(maxWidth, controlCell.button.titleLabel!.textRect(forBounds: bounds, limitedToNumberOfLines: 1).width + controlCell.buttonInsets.left + controlCell.buttonInsets.right)
        }

        subcontrolsViewDelegateDatasource.items = button.subcontrols

        viewModel.currentButton = button

        subcontrolsView.reloadData()

        DispatchQueue.main.asyncAfter(seconds: 0.1) {
            var height: CGFloat = 0

            for cell in self.subcontrolsView.visibleCells {
                height += cell.frame.height
            }

            self.subcontrolsViewHeightConstraint?.constant = height
            self.subcontrolsView.isHidden = false
            self.view.layoutIfNeeded()

            completion?()
        }
    }
}

extension ChatController: ActiveNetworkDisplaying {

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
