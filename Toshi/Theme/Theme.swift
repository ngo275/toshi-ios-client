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
import SweetFoundation

public final class Theme: NSObject {}

extension Theme {
    public static var borderHeight: CGFloat {
        return 1.0 / UIScreen.main.scale
    }
}

extension Theme {
    public static var randomColor: UIColor {
        let colors = [UIColor.lightGray, UIColor.green, UIColor.red, UIColor.magenta, UIColor.purple, UIColor.blue, UIColor.yellow]

        return colors[Int(arc4random_uniform(UInt32(colors.count)))]
    }

    public static var lightTextColor: UIColor {
        return .white
    }

    public static var mediumTextColor: UIColor {
        return UIColor(hex: "9A9B9B")
    }

    public static var darkTextColor: UIColor {
        return UIColor(hex: "161621")
    }

    public static var greyTextColor: UIColor {
        return UIColor(hex: "A4A4AB")
    }

    public static var lightGreyTextColor: UIColor {
        return UIColor(hex: "7D7C7C")
    }

    public static var lighterGreyTextColor: UIColor {
        return UIColor(hex: "F3F3F3")
    }

    public static var tintColor: UIColor {
        #if TOSHIDEV
            return UIColor(hex: "007AFF")
        #else
            return UIColor(hex: "01C236")
        #endif
    }

    public static var sectionTitleColor: UIColor {
        return UIColor(hex: "FF6D6D72")
    }

    public static var viewBackgroundColor: UIColor {
        return .white
    }

    public static var unselectedItemTintColor: UIColor {
        return UIColor(hex: "979ca4")
    }

    public static var settingsBackgroundColor: UIColor {
        return UIColor(hex: "F3F4F5")
    }

    public static var inputFieldBackgroundColor: UIColor {
        return UIColor(hex: "F1F1F1")
    }

    public static var navigationTitleTextColor: UIColor {
        return .black
    }

    public static var navigationBarColor: UIColor {
        return UIColor(hex: "FBFAFB")
    }

    public static var borderColor: UIColor {
        return UIColor(hex: "D7DBDC")
    }

    public static var actionButtonTitleColor: UIColor {
        return UIColor(hex: "0BBEE3")
    }

    public static var ratingBackground: UIColor {
        return UIColor(hex: "D1D1D1")
    }

    public static var ratingTint: UIColor {
        return UIColor(hex: "EB6E00")
    }

    public static var passphraseVerificationContainerColor: UIColor {
        return UIColor(hex: "EAEBEC")
    }

    public static var cellSelectionColor: UIColor {
        return UIColor(white: 0.95, alpha: 1)
    }

    public static var separatorColor: UIColor {
        return UIColor(white: 0.95, alpha: 1)
    }

    // MARK: - Message colours

    public static var incomingMessageBackgroundColor: UIColor {
        return UIColor(hex: "F1F0F0")
    }

    public static var outgoingMessageTextColor: UIColor {
        return .white
    }

    public static var incomingMessageTextColor: UIColor {
        return .black
    }

    public static var errorColor: UIColor {
        return UIColor(hex: "FF0000")
    }
}

extension Theme {

    static var sectionTitleFont: UIFont {
        return .preferredFont(forTextStyle: .footnote)
    }

    static func light(size: CGFloat) -> UIFont {
        return UIFont(name: "SFUIText-Light", size: size) ?? UIFont.systemFont(ofSize: CGFloat(size), weight: UIFontWeightLight)
    }

    static func regular(size: CGFloat) -> UIFont {
        return UIFont(name: "SFUIText-Regular", size: size) ?? UIFont.systemFont(ofSize: CGFloat(size), weight: UIFontWeightRegular)
    }

    static func semibold(size: CGFloat) -> UIFont {
        return UIFont(name: "SFUIText-Semibold", size: size) ?? UIFont.systemFont(ofSize: CGFloat(size), weight: UIFontWeightSemibold)
    }

    static func bold(size: CGFloat) -> UIFont {
        return UIFont(name: "SFUIText-Bold", size: size) ?? UIFont.systemFont(ofSize: CGFloat(size), weight: UIFontWeightBold)
    }

    static func medium(size: CGFloat) -> UIFont {
        return UIFont(name: "SFUIText-Medium", size: size) ?? UIFont.systemFont(ofSize: CGFloat(size), weight: UIFontWeightMedium)
    }
}
