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

import Foundation
import KeychainSwift

protocol Singleton: class {
    static var sharedInstance: Self { get }
}

@objc public enum YapInconsistencyError: Int {
    case none
    case missingDatabaseFile
    case missingKeychainPassword

    var description: String? {
        switch self {
        case .missingDatabaseFile:
            return Localized("yap_missing_db_file_error_description")
        case .missingKeychainPassword:
            return Localized("yap_missing_password_error_description")
        case .none:
            return nil
        }
    }
}

fileprivate struct UserDB {

    static let password = "DBPWD"

    static let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    static let dbFile = ".Signal.sqlite"
    static let walFile = ".Signal.sqlite-wal"
    static let shmFile = ".Signal.sqlite-shm"

    static let dbFilePath = documentsUrl.appendingPathComponent(dbFile).path
    static let walFilePath = documentsUrl.appendingPathComponent(walFile).path
    static let shmFilePath = documentsUrl.appendingPathComponent(shmFile).path

    struct Backup {
        static let directory = "UserDB-Backup"
        static let directoryPath = documentsUrl.appendingPathComponent(directory).path

        static let dbFile = ".Signal-Backup.sqlite"
        static let dbFilePath = documentsUrl.appendingPathComponent(directory).appendingPathComponent(".Signal-Backup-\(Cereal.shared.address).sqlite").path
    }
}

public final class Yap: NSObject, Singleton {
    @objc var database: YapDatabase?

    public var mainConnection: YapDatabaseConnection?

    @objc public static let sharedInstance = Yap()
    @objc public static var isUserDatabaseFileAccessible: Bool {
        return FileManager.default.fileExists(atPath: UserDB.dbFilePath)
    }

    @objc public static var isUserDatabasePasswordAccessible: Bool {
        return UserDefaults.standard.bool(forKey: UserDB.password)
    }

    @objc public static var inconsistentStateDescription = inconsistencyError.description

    @objc public static var inconsistencyError: YapInconsistencyError = isUserDatabaseFileAccessible ? .missingKeychainPassword : .missingDatabaseFile

    private override init() {
        super.init()

        if Yap.isUserDatabaseFileAccessible && Yap.isUserDatabasePasswordAccessible {
            createDBForCurrentUser()
            IDAPIClient.shared.updateContacts()
        }
    }

    public func setupForNewUser(with address: String) {
        useBackedDBIfNeeded()

        let keychain = KeychainSwift()
        keychain.synchronizable = false

        var dbPassowrd: Data
        if let loggedData = keychain.getData(UserDB.password) {
            dbPassowrd = loggedData
        } else {
            dbPassowrd = keychain.getData(address) ?? Randomness.generateRandomBytes(60).base64EncodedString().data(using: .utf8)!
        }
        keychain.set(dbPassowrd, forKey: UserDB.password, withAccess: .accessibleAfterFirstUnlockThisDeviceOnly)
        UserDefaults.standard.set(true, forKey: UserDB.password)

        createDBForCurrentUser()

        insert(object: address, for: TokenUser.currentLocalUserAddressKey)
        insert(object: TokenUser.current?.json, for: address, in: TokenUser.storedContactKey)

        createBackupDirectoryIfNeeded()
    }

    @objc public func wipeStorage() {
        if TokenUser.current?.verified == false {
            CrashlyticsLogger.log("Deleting database files for signed out user")

            removeDatabaseFileAndPassword()

            return
        }

        backupUserDBFile()
    }

    @objc public func processInconsistencyError() {
        CrashlyticsLogger.log("Deleting database files for signed out user")
        removeDatabaseFileAndPassword()
    }

    fileprivate func removeDatabaseFileAndPassword() {
        KeychainSwift().delete(UserDB.password)
        UserDefaults.standard.removeObject(forKey: UserDB.password)

        deleteFileIfNeeded(at: UserDB.dbFilePath)
        deleteFileIfNeeded(at: UserDB.walFilePath)
        deleteFileIfNeeded(at: UserDB.shmFilePath)
    }

    fileprivate func createDBForCurrentUser() {
        let options = YapDatabaseOptions()
        options.corruptAction = .fail

        options.cipherKeyBlock = {
            let keychain = KeychainSwift()
            keychain.synchronizable = false

            guard let userDatabasePassword = keychain.getData(UserDB.password) else {
                CrashlyticsLogger.log("No user database password", attributes: [.occured: "Cipher key block"])
                fatalError("No database password found in keychain")
            }

            return userDatabasePassword
        }

        database = YapDatabase(path: UserDB.dbFilePath, options: options)

        mainConnection = database?.newConnection()

        if database == nil {
            CrashlyticsLogger.log("Failed to create user database")
        } else {
            addSkipBackupAttributeToDatabasePath()
        }
    }

    private func addSkipBackupAttributeToDatabasePath() {
        let url = NSURL(fileURLWithPath: UserDB.dbFilePath)
        do {
            try url.setResourceValue(false, forKey: .isUbiquitousItemKey)
            try url.setResourceValue(true, forKey: .isExcludedFromBackupKey)
        } catch let error {
            CrashlyticsLogger.log("Failed to exclude DB from backup and sync \(error.localizedDescription)")
        }
    }

    fileprivate func createBackupDirectoryIfNeeded() {
        createdDirectoryIfNeeded(at: UserDB.Backup.directoryPath)
    }

    fileprivate func createdDirectoryIfNeeded(at path: String) {
        if FileManager.default.fileExists(atPath: path) == false {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
            } catch {}
        }
    }

    fileprivate func useBackedDBIfNeeded() {
        if TokenUser.current != nil, FileManager.default.fileExists(atPath: UserDB.Backup.dbFilePath) {
            CrashlyticsLogger.log("Using backup database for signed in user")
            try? FileManager.default.moveItem(atPath: UserDB.Backup.dbFilePath, toPath: UserDB.dbFilePath)
        }
    }

    fileprivate func deleteFileIfNeeded(at path: String) {
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    fileprivate func backupUserDBFile() {
        guard let user = TokenUser.current else {
            CrashlyticsLogger.log("No current user during session", attributes: [.occured: "Yap backup"])
            fatalError("No current user while backing up user db file")
        }

        CrashlyticsLogger.log("Backing up database file for signed out user")

        deleteFileIfNeeded(at: UserDB.walFilePath)
        deleteFileIfNeeded(at: UserDB.shmFilePath)

        let keychain = KeychainSwift()
        guard let currentPassword = keychain.getData(UserDB.password) else {
            CrashlyticsLogger.log("No database password found in keychain while database file exits", attributes: [.occured: "Yap backup"])
            fatalError("No database password found in keychain while database file exits")
        }

        keychain.set(currentPassword, forKey: user.address)

        try? FileManager.default.moveItem(atPath: UserDB.dbFilePath, toPath: UserDB.Backup.dbFilePath)

        KeychainSwift().delete(UserDB.password)
        UserDefaults.standard.removeObject(forKey: UserDB.password)
    }

    /// Insert a object into the database using the main thread default connection.
    ///
    /// - Parameters:
    ///   - object: Object to be stored. Must be serialisable. If nil, delete the record from the database.
    ///   - key: Key to store and retrieve object.
    ///   - collection: Optional. The name of the collection the object belongs to. Helps with organisation.
    ///   - metadata: Optional. Any serialisable object. Could be a related object, a description, a timestamp, a dictionary, and so on.
    public final func insert(object: Any?, for key: String, in collection: String? = nil, with metadata: Any? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.mainConnection?.asyncReadWrite { transaction in
                transaction.setObject(object, forKey: key, inCollection: collection, withMetadata: metadata)
            }
        }
    }

    public final func removeObject(for key: String, in collection: String? = nil) {
        mainConnection?.asyncReadWrite { transaction in
            transaction.removeObject(forKey: key, inCollection: collection)
        }
    }

    /// Checks whether an object was stored for a given key inside a given (optional) collection.
    ///
    /// - Parameter key: Key to check for the presence of a stored object.
    /// - Returns: Bool whether or not a certain object was stored for that key.
    public final func containsObject(for key: String, in collection: String? = nil) -> Bool {
        return retrieveObject(for: key, in: collection) != nil
    }

    /// Retrieve an object for a given key inside a given (optional) collection.
    ///
    /// - Parameters:
    ///   - key: Key used to store the object
    ///   - collection: Optional. The name of the collection the object was stored in.
    /// - Returns: The stored object.
    public final func retrieveObject(for key: String, in collection: String? = nil) -> Any? {
        var object: Any?
        mainConnection?.read { transaction in
            object = transaction.object(forKey: key, inCollection: collection)
        }

        return object
    }

    /// Retrieve all objects from a given collection.
    ///
    /// - Parameters:
    ///   - collection: The name of the collection to be retrieved.
    /// - Returns: The stored objects inside the collection.
    @objc public final func retrieveObjects(in collection: String) -> [Any] {
        var objects = [Any]()

        mainConnection?.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: collection) { _, object, _ in
                objects.append(object)
            }
        }

        return objects
    }
}
