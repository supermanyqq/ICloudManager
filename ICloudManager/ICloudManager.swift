//
//  ICloudManager.swift
//  TODO
//
//  Created by 桥余 on 2020/6/22.
//  Copyright © 2020 桥余. All rights reserved.
//

import Foundation
import CloudKit

public protocol RecordGenerateProtocol {
    func toRecord() -> CKRecord
}

public protocol RecordChangeDelegate {
    func recordDidChange(_ record: CKRecord)
    
    func deleteRecord(_ recordId: CKRecord.ID)
}

public final class ICloudManager {
    public static let shared = ICloudManager()
    
    public var delegate: RecordChangeDelegate?
    
    public var isCreateCustomZone: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "isCreateCustomZone")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isCreateCustomZone")
        }
    }
    public var isSubscribedPrivateChanges: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "isSubscribedPrivateChanges")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isSubscribedPrivateChanges")
        }
    }
    public var isSubscribedShareChanges: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "isSubscribedShareChanges")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isSubscribedShareChanges")
        }
    }
    public lazy var privateDB = CKContainer.default().privateCloudDatabase
    public lazy var shareDB = CKContainer.default().sharedCloudDatabase
    
    public func initIClound() {
        
        let zoneId = self.zoneId()
        
        let privateSubscriptionId = "private-changes"
        let shareSubscriptionId = "share-changes"
        
        let group = DispatchGroup()
        
        if !isCreateCustomZone {
            group.enter()
            let customZone = CKRecordZone.init(zoneID: zoneId)
            
            let createZoneOperation = CKModifyRecordZonesOperation.init(recordZonesToSave: [customZone], recordZoneIDsToDelete: nil)
            createZoneOperation.modifyRecordZonesCompletionBlock = { [weak self] (saved, deleted, error) in
                if error == nil {
                    self?.isCreateCustomZone = true
                } else {
                    print("create custom zone error \(error!.localizedDescription)")
                }
                group.leave()
            }
            createZoneOperation.qualityOfService = .userInitiated
            
            privateDB.add(createZoneOperation)
        }
        
        if !isSubscribedPrivateChanges {
            let operation = _createDatabaseSubscriptionOperation(subscriptionId: privateSubscriptionId)
            operation.modifySubscriptionsCompletionBlock = { [weak self] (subscriptions, deleteIds, error) in
                if error == nil {
                    self?.isSubscribedPrivateChanges = true
                } else {
                    print("subscribe private changes error \(error!.localizedDescription)")
                }
            }
            privateDB.add(operation)
        }
        
        if !isSubscribedShareChanges {
            let operation = _createDatabaseSubscriptionOperation(subscriptionId: shareSubscriptionId)
            operation.modifySubscriptionsCompletionBlock = { [weak self] (subscriptions, deleteIds, error) in
                if error == nil {
                    self?.isSubscribedShareChanges = true
                } else {
                    print("subscribe share changes error \(error!.localizedDescription)")
                }
            }
            shareDB.add(operation)
        }
    }
    
    private func _createDatabaseSubscriptionOperation(subscriptionId: String) -> CKModifySubscriptionsOperation {
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionId)
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        let operation = CKModifySubscriptionsOperation.init(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
        operation.qualityOfService = .utility
        
        return operation
    }
    
    public func addRecord(_ model: RecordGenerateProtocol) {
        let record = model.toRecord()
        let container = CKContainer.default()
        let privateDatabase = container.privateCloudDatabase
        privateDatabase.save(record) { (record, error) in
            if let error = error {
                print("iCloud save failed: \(error.localizedDescription)")
                return
            }
            print("iCloud 保存成功")
        }
    }
    
    public func deleteRecord(_ model: RecordGenerateProtocol) {
        let record = model.toRecord()
        let container = CKContainer.default()
        let privateDatabase = container.privateCloudDatabase
        privateDatabase.delete(withRecordID: record.recordID) { (recordID, error) in
            if let error = error {
                print("iCloud delete failed: \(error.localizedDescription)")
                return
            }
            print("iCloud 删除成功")
        }
    }
    
    public func updateRecord(_ model: RecordGenerateProtocol) {
        let operation =  CKModifyRecordsOperation()
        operation.recordsToSave = [model.toRecord()]
        operation.savePolicy = .changedKeys
        
        privateDB.add(operation)
    }
    
    public func queryRecords(by predicate: NSPredicate, recordType: String, completionHandler: @escaping ([CKRecord]) -> Void) {
        let sortDescriptor = NSSortDescriptor.init(key: "createDate", ascending: false)
        let query = CKQuery.init(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [sortDescriptor]
        
        var records: [CKRecord] = []
        
        let operation = CKQueryOperation(query: query)
        operation.zoneID = self.zoneId()
        operation.qualityOfService = .userInitiated
        
        operation.recordFetchedBlock = { record in
            records.append(record)
        }
        
        operation.queryCompletionBlock = { (cursor, error) in
            if let error = error {
                print("query \(predicate) error \(error.localizedDescription)")
                completionHandler([])
                return
            }
            completionHandler(records)
        }
        
        privateDB.add(operation)
    }
    
    public func fetchChanges(in databaseScope: CKDatabase.Scope, completion: @escaping () -> Void) {
        switch databaseScope {
        case .private:
            _fetchDatabaseChanges(database: privateDB, databaseTokenKey: "private", completion: completion)
        case .shared:
            _fetchDatabaseChanges(database: shareDB, databaseTokenKey: "shared", completion: completion)
        default:
            print("unsupport database")
            completion()
        }
    }
    
    public func zoneId() -> CKRecordZone.ID {
        return CKRecordZone.ID.init(zoneName: "Todos", ownerName: CKCurrentUserDefaultName)
    }
    
    // MARK: private methods
    
    /// 查询有改动的zone
    private func _fetchDatabaseChanges(database: CKDatabase, databaseTokenKey: String, completion: @escaping () -> Void) {
        var changeZoneIDs: [CKRecordZone.ID] = []
        
        let changeToken = _databaseChangeToken()
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: changeToken)
        
        operation.recordZoneWithIDChangedBlock = { zoneId in
            // 有改动的 zone id
            changeZoneIDs.append(zoneId)
        }
        
        operation.recordZoneWithIDWasDeletedBlock = { zoneId in
            // 被删除的zone
        }
        
        operation.changeTokenUpdatedBlock = { [weak self] token in
            // 更新 change token
            self?._updateDatabaseChangeToken(token)
        }
        
        operation.fetchDatabaseChangesCompletionBlock = { [weak self] (token, moreComing, error) in
            guard error == nil else {
                // TODO: CKErrorChangeTokenExpired 错误处理
                print("fetch database changes error \(error?.localizedDescription ?? "")")
                completion()
                return
            }
            
            if let token = token {
                self?._updateDatabaseChangeToken(token)
            }
            
            self?._fetchZoneChanges(database: database, databaseTokenKey: databaseTokenKey, zoneIDs: changeZoneIDs, completion: completion)
        }
        operation.qualityOfService = .userInitiated
        
        database.add(operation)
    }
    
    private func _fetchZoneChanges(database: CKDatabase, databaseTokenKey: String, zoneIDs: [CKRecordZone.ID], completion: @escaping () -> Void) {
        
        var optionsByRecordZoneID: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for zoneId in zoneIDs {
            let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            options.previousServerChangeToken = _zoneChangeToken()
            optionsByRecordZoneID[zoneId] = options
        }
        
//        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, optionsByRecordZoneID: optionsByRecordZoneID)
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, configurationsByRecordZoneID: optionsByRecordZoneID)
        
        operation.recordChangedBlock = { [weak self] record in
            // 更新数据
//            if (record.value(forKey: "name") as? String) != nil {
//                let model = ListTypeModel(record: record)
//                RealmManager.shared.update(model)
//                let userInfo = ["record": model]
//                NotificationCenter.post(customNotification: .updateRecord, object: nil, userInfo: userInfo)
//            } else {
//                let model = ListModel(record)
//                RealmManager.shared.update(model)
//                let userInfo = ["record": model]
//                NotificationCenter.post(customNotification: .updateRecord, object: nil, userInfo: userInfo)
//            }
            self?.delegate?.recordDidChange(record)
        }
        
        operation.recordWithIDWasDeletedBlock = { [weak self] (recordId, type) in
            // 删除数据
//            if let id = Int(recordId.recordName) {
//                RealmManager.shared.delete(id)
//                NotificationCenter.post(customNotification: .deleteRecord, object: nil, userInfo: ["id": id])
//            }
            self?.delegate?.deleteRecord(recordId)
        }
        
        operation.recordZoneChangeTokensUpdatedBlock = { [weak self] (zoneId, token, data) in
            if let token = token {
                self?._updateZoneChangeToken(token)
            }
        }
        
        operation.recordZoneFetchCompletionBlock = { [weak self] (recordId, token, data, moreComing, error) in
            guard error == nil else {
                // TODO: CKErrorChangeTokenExpired 错误处理
                print("record zone fetch error \(error?.localizedDescription ?? "")")
                return
            }
            if let token = token {
                self?._updateZoneChangeToken(token)
            }
        }
        
        operation.fetchRecordZoneChangesCompletionBlock = { error in
            if let error = error {
                print("featch record zone changes error \(error.localizedDescription)")
            }
            completion()
        }
        
        database.add(operation)
    }
    
    // MARK: icloud token 管理
    
    private func _updateDatabaseChangeToken(_ token: CKServerChangeToken?) {
            if let token = token {
    //            NSKeyedArchiver.archiveRootObject(token, toFile: PathManager.databaseChangeTokenPath())
                if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                    do {
                        try data.write(to: URL(string: _databaseChangeTokenPath())!)
                    } catch {
                        print("\(#line) \(#function) error \(error.localizedDescription)")
                    }
                }
            } else {
                try! FileManager.default.removeItem(atPath: _databaseChangeTokenPath())
            }
        }
        
    private func _databaseChangeToken() -> CKServerChangeToken? {
//        let data = NSKeyedUnarchiver.unarchiveObject(withFile: PathManager.databaseChangeTokenPath())
        if let data = try? Data(contentsOf: URL(string: _databaseChangeTokenPath())!),
            let token = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [CKServerChangeToken.self], from: data) as? CKServerChangeToken {
            return token
        }
        return nil
    }
    
    private func _updateZoneChangeToken(_ token: CKServerChangeToken?) {
        if let token = token {
//            NSKeyedArchiver.archiveRootObject(token, toFile: PathManager.zoneChangeTokenPath())
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                do {
                    try data.write(to: URL(string: _zoneChangeTokenPath())!)
                } catch {
                    print("\(#line) \(#function) error \(error.localizedDescription)")
                }
            }
        } else {
            try! FileManager.default.removeItem(atPath: _zoneChangeTokenPath())
        }
    }
    
    private func _zoneChangeToken() -> CKServerChangeToken? {
//        let data = NSKeyedUnarchiver.unarchiveObject(withFile: PathManager.zoneChangeTokenPath())
        if let data = try? Data(contentsOf: URL(string: _zoneChangeTokenPath())!),
            let token = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [CKServerChangeToken.self], from: data) as? CKServerChangeToken {
            return token
        }
        return nil
    }
    
    private func _databaseChangeTokenPath() -> String {
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let str = NSString(string: path)
        
        return str.appendingPathComponent("databaseServerChangeToken")
    }
    
    private func _zoneChangeTokenPath() -> String {
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let str = NSString(string: path)
        
        return str.appendingPathComponent("zoneServerChangeToken")
    }
}
