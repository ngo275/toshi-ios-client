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
import SweetSwift
import SweetFoundation

class ChatCell: UITableViewCell {
    var thread: TSThread? {
        didSet {
            // last visible message
            if let message = self.thread?.messages.last, let messageBody = message.body {

                switch SofaType(sofa: messageBody) {
                case .message:
                    lastMessageLabel.attributedText = NSMutableAttributedString(string: SofaMessage(content: messageBody).body, attributes: messageAttributes)
                case .paymentRequest:
                    lastMessageLabel.attributedText = NSMutableAttributedString(string: SofaPaymentRequest(content: messageBody).body, attributes: messageAttributes)
                default:
                    lastMessageLabel.attributedText = nil
                }
            } else {
                lastMessageLabel.attributedText = nil
            }

            // date
            if let date = self.thread?.lastMessageDate() {
                if DateTimeFormatter.isDate(date, sameDayAs: Date()) {
                    lastMessageDateLabel.text = DateTimeFormatter.timeFormatter.string(from: date)
                } else {
                    lastMessageDateLabel.text = DateTimeFormatter.dateFormatter.string(from: date)
                }
            }

            // unread badge
            if let thread = self.thread {
                let unreadMessagesCount = OWSMessageManager.shared().unreadMessages(in: thread)
                if unreadMessagesCount > 0 {
                    unreadLabel.text = "\(unreadMessagesCount)"
                    unreadView.isHidden = false
                    lastMessageDateLabel.textColor = Theme.tintColor
                } else {
                    unreadLabel.text = nil
                    unreadView.isHidden = true
                    lastMessageDateLabel.textColor = Theme.greyTextColor
                }
            }

            guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
            if let contact = delegate.contactsManager.tokenContact(forAddress: self.thread?.contactIdentifier() ?? "") {
                updateContact(contact)
            } else {
                IDAPIClient.shared.retrieveUser(username: thread?.contactIdentifier() ?? "") { [weak self] contact in
                    guard let contact = contact else { return }
                    self?.updateContact(contact)
                }
            }

            if let lastMessage = self.lastMessageLabel.text, !lastMessage.isEmpty {
                textGuideHeight.constant = 5
            } else {
                textGuideHeight.constant = 0
            }
        }
    }

    lazy var messageAttributes: [NSAttributedStringKey: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.5
        paragraphStyle.paragraphSpacing = -4
        paragraphStyle.lineBreakMode = .byTruncatingTail

        return [
            .kern: -0.4,
            .font: Theme.preferredRegularSmall(),
            .foregroundColor: Theme.greyTextColor,
            .paragraphStyle: paragraphStyle
        ]
    }()

    // Container that contains the unread label and
    // provides a colored background with content insets.
    lazy var unreadView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.tintColor
        view.layer.cornerRadius = 12
        view.clipsToBounds = true

        self.unreadLabel.font = Theme.preferredRegularSmall()
        self.unreadLabel.textColor = Theme.lightTextColor
        self.unreadLabel.textAlignment = .center
        view.addSubview(self.unreadLabel)

        self.unreadLabel.edges(to: view, insets: UIEdgeInsets(top: 0, left: 5, bottom: 0, right: -5))

        return view
    }()

    lazy var unreadLabel: UILabel = {
        let view = UILabel()
        view.font = Theme.semibold(size: 15)
        view.textColor = Theme.lightTextColor
        view.textAlignment = .center

        return view
    }()

    lazy var avatarImageView: AvatarImageView = {
        let view = AvatarImageView()

        return view
    }()

    lazy var usernameLabel: UILabel = {
        let view = UILabel()
        view.font = Theme.preferredSemibold()
        view.adjustsFontForContentSizeCategory = true
        view.textColor = Theme.darkTextColor

        return view
    }()

    lazy var lastMessageLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 2
        view.adjustsFontForContentSizeCategory = true

        return view
    }()

    lazy var lastMessageDateLabel: UILabel = {
        let view = UILabel()
        view.font = Theme.preferredRegularSmall()
        view.adjustsFontForContentSizeCategory = true
        view.textAlignment = .right
        view.textColor = Theme.tintColor

        return view
    }()

    lazy var separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.borderColor

        return view
    }()

    lazy var textGuide: UILayoutGuide = {
        UILayoutGuide()
    }()

    lazy var textGuideHeight: NSLayoutConstraint = {
        self.textGuide.height(0)
    }()

    override func prepareForReuse() {
        super.prepareForReuse()

        unreadLabel.text = nil
        avatarImageView.image = nil
        usernameLabel.text = nil
        lastMessageLabel.text = nil
        lastMessageDateLabel.text = nil
    }

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        accessoryType = .disclosureIndicator

        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Theme.cellSelectionColor
        self.selectedBackgroundView = selectedBackgroundView

        contentView.addSubview(unreadView)
        contentView.addSubview(avatarImageView)
        contentView.addSubview(usernameLabel)
        contentView.addSubview(lastMessageLabel)
        contentView.addSubview(lastMessageDateLabel)
        contentView.addSubview(separatorView)

        let avatarLayoutSpace = UILayoutGuide()
        contentView.addLayoutGuide(avatarLayoutSpace)
        let labelLayoutSpace = UILayoutGuide()
        contentView.addLayoutGuide(labelLayoutSpace)
        let indicatorsViewSpace = UILayoutGuide()
        contentView.addLayoutGuide(indicatorsViewSpace)

        contentView.addLayoutGuide(textGuide)

        let margin: CGFloat = 16.0
        let halfMargin: CGFloat = 8.0
        let imageSize: CGFloat = 48.0

        avatarLayoutSpace.left(to: contentView, offset: margin)
        avatarLayoutSpace.top(to: contentView, offset: margin)
        avatarLayoutSpace.bottom(to: contentView, offset: -margin)
        avatarLayoutSpace.height(imageSize, relation: .equalOrGreater)

        labelLayoutSpace.leftToRight(of: avatarLayoutSpace, offset: margin)
        labelLayoutSpace.top(to: contentView, offset: halfMargin)
        labelLayoutSpace.bottom(to: contentView, offset: -halfMargin)

        indicatorsViewSpace.top(to: labelLayoutSpace)
        indicatorsViewSpace.leftToRight(of: labelLayoutSpace, offset: margin)
        indicatorsViewSpace.right(to: contentView)
        indicatorsViewSpace.bottom(to: contentView)

        avatarImageView.size(CGSize(width: imageSize, height: imageSize))
        avatarImageView.centerY(to: avatarLayoutSpace)
        avatarImageView.left(to: avatarLayoutSpace)
        avatarImageView.right(to: avatarLayoutSpace)

        usernameLabel.top(to: labelLayoutSpace)
        usernameLabel.left(to: labelLayoutSpace)
        usernameLabel.right(to: labelLayoutSpace)

        textGuide.topToBottom(of: usernameLabel)
        textGuide.left(to: labelLayoutSpace)
        textGuide.right(to: labelLayoutSpace)

        lastMessageLabel.topToBottom(of: textGuide)
        lastMessageLabel.left(to: labelLayoutSpace)
        lastMessageLabel.right(to: labelLayoutSpace)
        lastMessageLabel.bottom(to: labelLayoutSpace)

        lastMessageDateLabel.top(to: indicatorsViewSpace)
        lastMessageDateLabel.left(to: indicatorsViewSpace)
        lastMessageDateLabel.right(to: indicatorsViewSpace)

        unreadView.topToBottom(of: lastMessageDateLabel, offset: 12)
        unreadView.right(to: indicatorsViewSpace)
        unreadView.height(24)
        unreadView.width(24, relation: .equalOrGreater)

        separatorView.left(to: avatarLayoutSpace)
        separatorView.right(to: self)
        separatorView.height(.lineHeight)
        separatorView.bottom(to: contentView)
    }

    required init?(coder _: NSCoder) {
        fatalError()
    }

    func updateContact(_ contact: TokenUser) {
        usernameLabel.text = !contact.name.isEmpty ? contact.name : contact.displayUsername

        AvatarManager.shared.avatar(for: contact.avatarPath) { [weak self] image, path in
            if contact.avatarPath == path {
                self?.avatarImageView.image = image
            }
        }
    }
}
