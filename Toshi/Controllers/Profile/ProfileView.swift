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

protocol PersonalProfileViewDelegate: class {
    func didTapEditProfileButton(in view: ProfileView)
}

protocol ProfileViewDelegate: class {
    func didTapMessageContactButton(in view: ProfileView)
    func didTapAddContactButton(in view: ProfileView)
    func didTapPayButton(in view: ProfileView)
    func didTapRateUser(in view: ProfileView)
}

class ProfileView: UIView {

    enum ViewType {
        case profile
        case personalProfile
        case personalProfileReadOnly
    }

    weak var personalProfileDelegate: PersonalProfileViewDelegate?
    weak var profileDelegate: ProfileViewDelegate?

    func setContact(_ user: TokenUser) {

        if !user.name.isEmpty {
            nameLabel.text = user.name
            usernameLabel.text = user.displayUsername
        } else {
            nameLabel.text = user.displayUsername
            usernameLabel.text = nil
        }

        aboutContentLabel.text = user.about
        locationContentLabel.text = user.location
    }

    lazy var avatarImageView = AvatarImageView()

    lazy var nameLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.font = Theme.preferredTitle2()
        view.adjustsFontForContentSizeCategory = true

        return view
    }()

    lazy var usernameLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.font = Theme.preferredRegularMedium()
        view.adjustsFontForContentSizeCategory = true
        view.textColor = Theme.greyTextColor

        return view
    }()

    lazy var aboutContentLabel: UILabel = {
        let view = UILabel()
        view.font = Theme.preferredRegular()
        view.adjustsFontForContentSizeCategory = true
        view.numberOfLines = 0

        return view
    }()

    lazy var locationContentLabel: UILabel = {
        let view = UILabel()
        view.font = Theme.preferredRegularMedium()
        view.adjustsFontForContentSizeCategory = true
        view.textColor = Theme.lightGreyTextColor
        view.numberOfLines = 0

        return view
    }()

    fileprivate lazy var actionsSeparatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.borderColor
        view.set(height: 1.0 / UIScreen.main.scale)

        return view
    }()

    lazy var actionView: ContactActionView = {
        let view = ContactActionView()

        view.messageButton.addTarget(self, action: #selector(self.didTapMessageContactButton), for: .touchUpInside)
        view.addFavoriteButton.addTarget(self, action: #selector(self.didTapAddContactButton), for: .touchUpInside)
        view.payButton.addTarget(self, action: #selector(self.didTapPayButton), for: .touchUpInside)

        return view
    }()

    fileprivate lazy var editProfileButton: UIButton = {
        let view = UIButton()
        view.setAttributedTitle(NSAttributedString(string: "Edit Profile", attributes: [.font: Theme.preferredRegular(), .foregroundColor: Theme.tintColor]), for: .normal)
        view.setAttributedTitle(NSAttributedString(string: "Edit Profile", attributes: [.font: Theme.preferredRegular(), .foregroundColor: Theme.lightGreyTextColor]), for: .highlighted)
        view.addTarget(self, action: #selector(didTapEditProfileButton), for: .touchUpInside)
        view.titleLabel?.adjustsFontForContentSizeCategory = true
        view.clipsToBounds = true
        
        return view
    }()

    lazy var reputationTitle: UILabel = {
        let view = UILabel()
        view.font = Theme.preferredFootnote()
        view.textColor = Theme.sectionTitleColor
        view.text = "REPUTATION"
        view.adjustsFontForContentSizeCategory = true

        return view
    }()

    fileprivate lazy var contentBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.viewBackgroundColor

        return view
    }()

    fileprivate lazy var contentSeparatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.lightGrayBackgroundColor
        view.layer.borderColor = Theme.borderColor.cgColor
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.set(height: 1.0 / UIScreen.main.scale)

        return view
    }()

    fileprivate lazy var reputationSeparatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.lightGrayBackgroundColor
        view.layer.borderColor = Theme.borderColor.cgColor
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.set(height: 1.0 / UIScreen.main.scale)

        return view
    }()

    lazy var rateThisUserButton: UIButton = {
        let view = UIButton()
        view.setTitle("Rate this user", for: .normal)
        view.setTitleColor(Theme.tintColor, for: .normal)
        view.setTitleColor(Theme.greyTextColor, for: .highlighted)
        view.titleLabel?.font = Theme.preferredRegular()
        view.titleLabel?.adjustsFontForContentSizeCategory = true
        view.clipsToBounds = true

        view.addTarget(self, action: #selector(self.didTapRateUser), for: .touchUpInside)
        
        return view
    }()

    fileprivate lazy var bottomSeparatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.lightGrayBackgroundColor
        view.layer.borderColor = Theme.borderColor.cgColor
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.set(height: 1.0 / UIScreen.main.scale)

        return view
    }()

    lazy var reputationView = ReputationView()

    lazy var reputationBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.viewBackgroundColor

        return view
    }()

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = true
        view.delaysContentTouches = false

        return view
    }()

    private lazy var container = UIView()

    init(viewType: ViewType) {
        super.init(frame: CGRect.zero)

        addSubviewsAndConstraints(for: viewType)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func addSubviewsAndConstraints(for viewType: ViewType) {
        let editProfileButtonHeight: CGFloat
        let actionSeparatorMargin: CGFloat
        let rateThisUserButtonHeight: CGFloat

        switch viewType {
            case .profile:
                editProfileButtonHeight = 0.0
                actionSeparatorMargin = 8.0
                actionView.alpha = 1.0
                rateThisUserButtonHeight = 44.0
            case .personalProfile:
                editProfileButtonHeight = 50.0
                actionSeparatorMargin = 0.0
                actionView.alpha = 0.0
                rateThisUserButtonHeight = 0.0
            case .personalProfileReadOnly:
                editProfileButtonHeight = 0.0
                actionSeparatorMargin = 0.0
                actionsSeparatorView.alpha = 0.0
                actionView.alpha = 0.0
                rateThisUserButtonHeight = 0.0
        }

        let margin: CGFloat = 15
        let avatarSize = CGSize(width: 60, height: 60)

        addSubview(scrollView)
        scrollView.edges(to: self)

        scrollView.addSubview(container)
        container.edges(to: scrollView)
        container.width(to: scrollView)

        container.addSubview(contentBackgroundView)

        contentBackgroundView.top(to: container)
        contentBackgroundView.left(to: container)
        contentBackgroundView.right(to: container)

        contentBackgroundView.addSubview(avatarImageView)
        contentBackgroundView.addSubview(nameLabel)
        contentBackgroundView.addSubview(usernameLabel)
        contentBackgroundView.addSubview(aboutContentLabel)
        contentBackgroundView.addSubview(locationContentLabel)
        contentBackgroundView.addSubview(actionsSeparatorView)
        contentBackgroundView.addSubview(actionView)
        contentBackgroundView.addSubview(editProfileButton)
        contentBackgroundView.addSubview(contentSeparatorView)

        container.addSubview(reputationTitle)

        container.addSubview(reputationBackgroundView)

        reputationBackgroundView.topToBottom(of: contentBackgroundView, offset: 66)
        reputationBackgroundView.left(to: container)
        reputationBackgroundView.bottom(to: container)
        reputationBackgroundView.right(to: container)

        reputationBackgroundView.addSubview(reputationSeparatorView)
        reputationBackgroundView.addSubview(reputationView)
        reputationBackgroundView.addSubview(rateThisUserButton)
        reputationBackgroundView.addSubview(bottomSeparatorView)

        avatarImageView.size(avatarSize)
        avatarImageView.origin(to: contentBackgroundView, insets: CGVector(dx: margin, dy: margin * 2))

        let nameContainer = UILayoutGuide()
        contentBackgroundView.addLayoutGuide(nameContainer)

        nameContainer.top(to: contentBackgroundView, offset: margin * 2)
        nameContainer.leftToRight(of: avatarImageView, offset: margin)
        nameContainer.right(to: contentBackgroundView, offset: -margin)

        nameLabel.height(25, relation: .equalOrGreater, priority: .defaultHigh)
        nameLabel.top(to: nameContainer)
        nameLabel.left(to: nameContainer)
        nameLabel.right(to: nameContainer)

        usernameLabel.height(25, relation: .equalOrGreater, priority: .defaultHigh)
        usernameLabel.topToBottom(of: nameLabel)

        usernameLabel.left(to: nameContainer)
        usernameLabel.bottom(to: nameContainer)
        usernameLabel.right(to: nameContainer)

        aboutContentLabel.topToBottom(of: nameContainer, offset: margin)
        aboutContentLabel.left(to: contentBackgroundView, offset: margin)
        aboutContentLabel.right(to: contentBackgroundView, offset: -margin)

        locationContentLabel.topToBottom(of: aboutContentLabel, offset: 7)
        locationContentLabel.left(to: contentBackgroundView, offset: margin)
        locationContentLabel.right(to: contentBackgroundView, offset: -margin)

        actionsSeparatorView.height(.lineHeight)
        actionsSeparatorView.topToBottom(of: locationContentLabel, offset: margin)
        actionsSeparatorView.left(to: contentBackgroundView, offset: actionSeparatorMargin)
        actionsSeparatorView.right(to: contentBackgroundView, offset: -actionSeparatorMargin)

        actionView.height(80.0)
        actionView.topToBottom(of: actionsSeparatorView)
        actionView.left(to: contentBackgroundView)
        actionView.right(to: contentBackgroundView)

        let topView = viewType == .profile ? actionView : actionsSeparatorView
        editProfileButton.topToBottom(of: topView)
        editProfileButton.height(editProfileButtonHeight)
        editProfileButton.left(to: contentBackgroundView)
        editProfileButton.right(to: contentBackgroundView)

        contentSeparatorView.height(.lineHeight)
        contentSeparatorView.topToBottom(of: editProfileButton)
        contentSeparatorView.left(to: contentBackgroundView)
        contentSeparatorView.right(to: contentBackgroundView)
        contentSeparatorView.bottom(to: contentBackgroundView)

        reputationTitle.bottomToTop(of: reputationBackgroundView, offset: -7)
        reputationTitle.left(to: container, offset: 16)
        reputationTitle.right(to: container, offset: -16)
        reputationTitle.height(60, relation: .equalOrLess)

        reputationSeparatorView.height(.lineHeight)
        reputationSeparatorView.top(to: reputationBackgroundView)
        reputationSeparatorView.left(to: reputationBackgroundView)
        reputationSeparatorView.right(to: reputationBackgroundView)

        reputationView.topToBottom(of: reputationSeparatorView, offset: 40)
        reputationView.left(to: reputationBackgroundView, offset: 34)
        reputationView.right(to: reputationBackgroundView, offset: -40)

        rateThisUserButton.topToBottom(of: reputationView, offset: 20)
        rateThisUserButton.left(to: reputationBackgroundView)
        rateThisUserButton.right(to: reputationBackgroundView)
        rateThisUserButton.height(rateThisUserButtonHeight)

        bottomSeparatorView.height(.lineHeight)
        bottomSeparatorView.topToBottom(of: rateThisUserButton)
        bottomSeparatorView.left(to: reputationBackgroundView)
        bottomSeparatorView.right(to: reputationBackgroundView)
        bottomSeparatorView.bottom(to: reputationBackgroundView)
    }

    @objc private func didTapMessageContactButton() {
        profileDelegate?.didTapMessageContactButton(in: self)
    }

    @objc private func didTapAddContactButton() {
        profileDelegate?.didTapAddContactButton(in: self)
    }

    @objc private func didTapPayButton() {
        profileDelegate?.didTapPayButton(in: self)
    }

    @objc private func didTapEditProfileButton() {
        personalProfileDelegate?.didTapEditProfileButton(in: self)
    }

    @objc private func didTapRateUser() {
        profileDelegate?.didTapRateUser(in: self)
    }
}
