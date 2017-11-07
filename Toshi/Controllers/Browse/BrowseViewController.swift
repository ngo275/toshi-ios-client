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

import SweetFoundation
import UIKit
import SweetUIKit

enum BrowseContentSection {
    case topRatedApps
    case featuredApps
    case topRatedPublicUsers
    case latestPublicUsers

    var title: String {
        switch self {
        case .topRatedApps:
            return Localized("browse-top-rated-apps")
        case .featuredApps:
            return Localized("browse-featured-apps")
        case .topRatedPublicUsers:
            return Localized("browse-top-rated-public-users")
        case .latestPublicUsers:
            return Localized("browse-latest-public-users")
        }
    }
}

class BrowseViewController: SearchableCollectionController {

    fileprivate var contentSections: [BrowseContentSection] = [.topRatedApps, .featuredApps, .topRatedPublicUsers, .latestPublicUsers]

    fileprivate var items: [[TokenUser]] = [[], [], [], []]

    fileprivate lazy var searchResultView: BrowseSearchResultView = {
        let view = BrowseSearchResultView()
        view.alpha = 0

        return view
    }()

    fileprivate lazy var openURLButton: OpenURLButton = {
        let view = OpenURLButton(withAutoLayout: true)
        view.addTarget(self, action: #selector(self.didTapOpenURLButton), for: .touchUpInside)
        view.isHidden = true

        return view
    }()

    fileprivate lazy var openButtonAttributes: [NSAttributedStringKey: Any] = {
        return [.foregroundColor: Theme.tintColor, .font: Theme.regular(size: 14)]
    }()

    fileprivate var openURLButtonTopAnchor: NSLayoutConstraint!

    private lazy var layout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        return layout
    }()
    
    var topInset: CGFloat {
        return (navigationController?.navigationBar.bounds.height ?? 0) + searchController.searchBar.frame.height + UIApplication.shared.statusBarFrame.height
    }
    
    var bottomInset: CGFloat {
        return tabBarController?.tabBar.bounds.height ?? 0
    }

    public init() {
        super.init()

        collectionView.register(BrowseCollectionViewCell.self)
        automaticallyAdjustsScrollViewInsets = false
    }

    required public init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = Localized("browse-navigation-title")

        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = Theme.viewBackgroundColor
        collectionView.dataSource = self
        collectionView.setCollectionViewLayout(layout, animated: false)
        collectionView.delegate = self
        
        if #available(iOS 11.0, *) {
            collectionView.contentInsetAdjustmentBehavior = .never
        }
        
        collectionView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        
        searchBar.delegate = self
        searchBar.barTintColor = Theme.viewBackgroundColor
        searchBar.tintColor = Theme.tintColor
        searchBar.placeholder = Localized("browse-search-placeholder")

        let searchField = searchBar.value(forKey: "searchField") as? UITextField
        searchField?.backgroundColor = Theme.inputFieldBackgroundColor
        
        addSubviewsAndConstraints()
    }

    private func addSubviewsAndConstraints() {
        view.addSubview(searchResultView)
        view.addSubview(openURLButton)

        searchResultView.top(to: view, offset: 64)
        searchResultView.left(to: view)
        searchResultView.bottom(to: view)
        searchResultView.right(to: view)

        openURLButton.height(44)
        openURLButton.left(to: view).isActive = true
        openURLButton.right(to: view).isActive = true
        openURLButtonTopAnchor = openURLButton.top(to: collectionView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        preferLargeTitleIfPossible(true)

        loadItems()

        collectionView.collectionViewLayout.invalidateLayout()

        if let indexPathForSelectedRow = searchResultView.indexPathForSelectedRow {
            searchResultView.deselectRow(at: indexPathForSelectedRow, animated: true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        searchBar.resignFirstResponder()
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        
        collectionView.scrollIndicatorInsets.top = max(0, scrollView.contentOffset.y * -1)
        collectionView.scrollIndicatorInsets.bottom = bottomInset
    }

    func dismissSearchIfNeeded() {
        if let searchText = searchBar.text, searchText.length > 0 {
            self.searchController.dismiss(animated: false, completion: nil)
        }
    }

    private func showResults(_ apps: [TokenUser]?, at index: Int, _ error: Error? = nil) {
        if let error = error {
            let alertController = UIAlertController.errorAlert(error as NSError)
            Navigator.presentModally(alertController)
        }

        self.items[index] = apps ?? []
        self.collectionView.collectionViewLayout.invalidateLayout()
        self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
    }

    private func loadItems() {

        AppsAPIClient.shared.getTopRatedApps { [weak self] apps, error in
            self?.showResults(apps, at: 0, error)
        }
        
        AppsAPIClient.shared.getFeaturedApps { [weak self] apps, error in
            self?.showResults(apps, at: 1, error)
        }
        
        IDAPIClient.shared.getTopRatedPublicUsers { [weak self] users, error in
            self?.showResults(users, at: 2, error)
        }
        
        IDAPIClient.shared.getLatestPublicUsers { [weak self] users, error in
            self?.showResults(users, at: 3, error)
        }
    }

    private func avatar(for indexPath: IndexPath, in section: Int, completion: @escaping ((UIImage?) -> Void)) {

        guard let section = items.element(at: section), let item = section.element(at: indexPath.item) else {
            completion(nil)
            return
        }

        AvatarManager.shared.avatar(for: item.avatarPath, completion: { image, _ in
            completion(image)
        })
    }

    @objc
    fileprivate func reload(searchText: String) {

        if searchText.isValidURL {
            let title = NSAttributedString(string: searchText, attributes: openButtonAttributes)
            openURLButton.setAttributedTitle(title)

            searchResultView.searchResults = []

            showOpenURLButton()
        } else {
            hideOpenURLButtonIfNeeded()
            IDAPIClient.shared.searchContacts(name: searchText) { [weak self] users in

                if searchText == self?.searchBar.text {
                    self?.searchResultView.searchResults = users
                }
            }
        }
    }

    fileprivate func showOpenURLButton() {
        openURLButton.isHidden = false
        openURLButtonTopAnchor.constant = topInset
        
        UIView.animate(withDuration: 1, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 10, options: .easeOutFromCurrentStateWithUserInteraction, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    fileprivate func hideOpenURLButtonIfNeeded() {
        openURLButtonTopAnchor.constant = 0
        
        UIView.animate(withDuration: 1, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: .easeOutFromCurrentStateWithUserInteraction, animations: {
            self.view.layoutIfNeeded()
        }) { _ in
            self.openURLButton.setAttributedTitle(nil)
            self.openURLButton.isHidden = true
        }
    }

    @objc
    fileprivate func didTapOpenURLButton() {
        guard let string = searchController.searchBar.text, let url = URL(string: string) else { return }

        let sofaController = SOFAWebController()

        sofaController.load(url: url)
        navigationController?.pushViewController(sofaController, animated: true)
    }
}

extension BrowseViewController: UISearchBarDelegate {

    func searchBar(_: UISearchBar, textDidChange searchText: String) {

        searchResultView.alpha = 1

        if searchText.isEmpty {
            searchResultView.searchResults = []
            hideOpenURLButtonIfNeeded()
        }

        reload(searchText: searchText)
    }

    func searchBarCancelButtonClicked(_: UISearchBar) {
        searchResultView.alpha = 0
        searchResultView.searchResults = []
        hideOpenURLButtonIfNeeded()
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        if let sectionedCollectionView = collectionView as? SectionedCollectionView {
            let cell = sectionedCollectionView.dequeue(BrowseEntityCollectionViewCell.self, for: indexPath)

            if let section = items.element(at: sectionedCollectionView.section), let item = section.element(at: indexPath.item) {
                if !item.name.isEmpty {
                    cell.nameLabel.text = item.name
                } else {
                    cell.nameLabel.text = item.isApp ? item.category : item.username
                }

                cell.avatarImageView.image = AvatarManager.shared.cachedAvatar(for: item.avatarPath)
                
                if let averageRating = item.averageRating {
                    cell.ratingView.set(rating: averageRating)
                }
            }

            return cell
        }

        let contentSection = contentSections[indexPath.item]

        let cell = collectionView.dequeue(BrowseCollectionViewCell.self, for: indexPath)
        cell.collectionView.dataSource = self
        cell.collectionView.reloadData()
        cell.collectionView.collectionViewLayout.invalidateLayout()
        cell.collectionView.section = indexPath.item
        cell.contentSection = contentSection
        cell.collectionViewDelegate = self
        cell.divider.isHidden = contentSection == .latestPublicUsers

        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection _: Int) -> Int {

        if let collectionView = collectionView as? SectionedCollectionView {
            return items[collectionView.section].count
        }

        return items.count
    }
}

extension BrowseViewController {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let numberOfItems = items[indexPath.row].count
        let itemHeight: CGFloat = (numberOfItems == 0) ? 0 : 247
        
        return CGSize(width: UIScreen.main.bounds.width, height: itemHeight)
    }
}

extension BrowseViewController: BrowseCollectionViewCellSelectionDelegate {

    func seeAll(for contentSection: BrowseContentSection) {
        let controller = BrowseAllViewController(contentSection)
        controller.title = contentSection.title
        Navigator.push(controller)
    }

    func didSelectItem(at indexPath: IndexPath, collectionView: SectionedCollectionView) {

        if let section = items.element(at: collectionView.section), let item = section.element(at: indexPath.item) {
            Navigator.push(ContactController(contact: item))
        }
    }

    func willDisplayCell(_ cell: UICollectionViewCell, at indexPath: IndexPath, _ collectionView: UICollectionView) {

        if let sectionedCollectionView = collectionView as? SectionedCollectionView, let cell = cell as? BrowseEntityCollectionViewCell {

            avatar(for: indexPath, in: sectionedCollectionView.section, completion: { [weak self] image in

                guard let strongSelf = self else { return }

                let visibleEntities = sectionedCollectionView.indexPathsForVisibleItems.map { $0.item }
                let visibleCategories = strongSelf.collectionView.indexPathsForVisibleItems.map { $0.item }

                if visibleEntities.contains(indexPath.item) && visibleCategories.contains(sectionedCollectionView.section) {
                    cell.avatarImageView.image = image
                }
            })
        }
    }
}
