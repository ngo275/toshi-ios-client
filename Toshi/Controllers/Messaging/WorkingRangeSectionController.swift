import Foundation
import UIKit

protocol WorkingRangeDataSource: class {
    func messagePosition(for index: Int) -> MessagePositionType
    func didPrepareCell(for message: MessageModel)
}

final class WorkingRangeSectionController: ListSectionController, ListWorkingRangeDelegate {

    var datasource: WorkingRangeDataSource?
    var message: MessageModel?
    var positionType: MessagePositionType = .single
    var avatarPath: String?

    deinit {

    }

    override init() {
        super.init()
        
        workingRangeDelegate = self
    }

    override func numberOfItems() -> Int {
        return 1
    }

    override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: UIScreen.main.bounds.width, height: 70)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {

        var cellClass: AnyClass?

        guard let message = self.message as MessageModel? else {
            fatalError("No message on WorkingRangeSectionController while trying to dequeue a cell")
        }

        switch message.type {
        case .simple:
            cellClass = MessagesTextCell.self
        case .image:
            cellClass = MessagesImageCell.self
        case .payment, .paymentRequest:
            cellClass = MessagesPaymentCell.self
        default:
            break
        }

        guard cellClass != nil else { fatalError("No valid cell class found in WorkingRangeSectionController") }
        let cell = collectionContext!.dequeueReusableCell(of: cellClass!, for: self, at: index)

        if let cell = cell as? MessagesBasicCell {

            if !message.isOutgoing, let avatarPath = self.avatarPath as String? {
                AvatarManager.shared.avatar(for: avatarPath, completion: { image, _ in
                    cell.avatarImageView.image = image
                })
            }

            cell.isOutGoing = message.isOutgoing
            cell.positionType = self.datasource?.messagePosition(for: index) ?? .single
        }

        if let cell = cell as? MessagesImageCell, message.type == .image {
            cell.messageImage = message.image
        } else if let cell = cell as? MessagesPaymentCell, (message.type == .payment) || (message.type == .paymentRequest), let signalMessage = message.signalMessage {
            cell.titleLabel.text = message.title
            cell.subtitleLabel.text = message.subtitle
            cell.messageLabel.text = message.text
            cell.setPaymentState(signalMessage.paymentState, for: message.type)
            //cell.selectionDelegate = self

            let isPaymentOpen = (message.signalMessage?.paymentState ?? .none) == .none
            let isMessageActionable = message.isActionable

            let isOpenPaymentRequest = isMessageActionable && isPaymentOpen
            if isOpenPaymentRequest {
               // showActiveNetworkViewIfNeeded()
            }

        } else if let cell = cell as? MessagesTextCell, message.type == .simple {
            cell.messageText = message.text
        }

        datasource?.didPrepareCell(for: message)

        return cell
    }

    override func didUpdate(to object: Any) {
        guard let model = object as? MessageModel else { return }

        self.message = model
    }

    // MARK: ListWorkingRangeDelegate
    func listAdapter(_ listAdapter: ListAdapter, sectionControllerWillEnterWorkingRange sectionController: ListSectionController) {

    }

    func listAdapter(_ listAdapter: ListAdapter, sectionControllerDidExitWorkingRange sectionController: ListSectionController) {

    }
    
}
