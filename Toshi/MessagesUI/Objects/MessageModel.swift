import Foundation
import UIKit

enum MessageType {
    case simple
    case image
    case paymentRequest
    case payment
    case status
}

class MessageModel: NSObject, ListDiffable {
    /**
     Returns a key that uniquely identifies the object.
     
     @return A key that can be used to uniquely identify the object.
     
     @note Two objects may share the same identifier, but are not equal. A common pattern is to use the `NSObject`
     category for automatic conformance. However this means that objects will be identified on their
     pointer value so finding updates becomes impossible.
     
     @warning This value should never be mutated.
     */
    func diffIdentifier() -> NSObjectProtocol {
        return self.hash as NSObjectProtocol
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        return self.diffIdentifier().isEqual(object!.diffIdentifier())
    }

    private let message: Message

    var type: MessageType
    var title: String?
    var subtitle: String?
    let text: String?
    let isOutgoing: Bool

    var identifier: String {
        return message.uniqueIdentifier()
    }

    override var description: String {
        return "Title:\(String(describing: title)), subtitle:\(String(describing: subtitle)), text:\(String(describing: text))\n"
    }

    var image: UIImage? {
        if message.image != nil {
            return message.image
        } else {
            return nil
        }
    }

    var isActionable: Bool
    var signalMessage: TSMessage?
    var sofaWrapper: SofaWrapper?

    public var fiatValueString: String?
    public var ethereumValueString: String?

    init(message: Message) {
        self.message = message

        isOutgoing = message.isOutgoing

        if let title = message.title, !title.isEmpty {
            self.title = title
        } else {
            title = nil
        }

        fiatValueString = nil
        ethereumValueString = nil

        subtitle = message.subtitle
        text = message.text

        signalMessage = message.signalMessage
        sofaWrapper = message.sofaWrapper

        if message.sofaWrapper?.type == .paymentRequest {
            type = .paymentRequest
            isActionable = true

            fiatValueString = message.fiatValueString
            ethereumValueString = message.ethereumValueString

            if let fiatValueString = message.fiatValueString {
                title = "Request for \(fiatValueString)"
            }
            subtitle = message.ethereumValueString

        } else if message.sofaWrapper?.type == .payment {
            type = .payment
            isActionable = false

            fiatValueString = message.fiatValueString
            ethereumValueString = message.ethereumValueString

            if let fiatValueString = message.fiatValueString {
                title = "Payment for \(fiatValueString)"
            }
            subtitle = message.ethereumValueString

        } else if message.image != nil {
            type = .image
            isActionable = false
        } else {
            type = .simple
            isActionable = false
        }
    }
}
