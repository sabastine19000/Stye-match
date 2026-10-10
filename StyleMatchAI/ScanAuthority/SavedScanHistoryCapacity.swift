import Foundation

enum SavedScanHistoryCapacity {
    static let maximumRecords = 500

    static func canInsert(recordID: String, existingRecordIDs: Set<String>) -> Bool {
        existingRecordIDs.contains(recordID) || existingRecordIDs.count < maximumRecords
    }
}
