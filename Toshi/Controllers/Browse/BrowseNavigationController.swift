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

public class BrowseNavigationController: UINavigationController {
    
    static let selectedAppKey = "Restoration::SelectedApp"

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
    
    public override init(rootViewController: UIViewController) {
        
        if let profileData = UserDefaults.standard.data(forKey: BrowseNavigationController.selectedAppKey) {
            super.init(nibName: nil, bundle: nil)
            guard let json = (try? JSONSerialization.jsonObject(with: profileData, options: [])) as? [String: Any] else { return }
            
            viewControllers = [rootViewController, ProfileViewController(contact: TokenUser(json: json))]
            configureTabBarItem()
        } else {
            super.init(rootViewController: rootViewController)
        }
    }
    
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configureTabBarItem()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configureTabBarItem() {
        tabBarItem = UITabBarItem(title: Localized("tab_bar_title_browse"), image: #imageLiteral(resourceName: "tab1"), tag: 0)
        tabBarItem.titlePositionAdjustment.vertical = TabBarItemTitleOffset
    }

    public override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)

        if let viewController = viewController as? ProfileViewController {
            UserDefaults.standard.setValue(viewController.contact.json, forKey: BrowseNavigationController.selectedAppKey)
        }
    }

    public override func popViewController(animated: Bool) -> UIViewController? {
        UserDefaults.standard.removeObject(forKey: BrowseNavigationController.selectedAppKey)
        return super.popViewController(animated: animated)
    }

    public override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        UserDefaults.standard.removeObject(forKey: BrowseNavigationController.selectedAppKey)
        return super.popToRootViewController(animated: animated)
    }

    public override func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        UserDefaults.standard.removeObject(forKey: BrowseNavigationController.selectedAppKey)
        return super.popToViewController(viewController, animated: animated)
    }
}
