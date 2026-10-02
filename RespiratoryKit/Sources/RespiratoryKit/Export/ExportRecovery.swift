import Foundation

/// Export archives are disposable copies. Recover cleanup if the process ended while sharing.
public enum ExportRecovery {
    public static func removeAbandonedArchives(in directory: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        for item in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where item.lastPathComponent.hasPrefix("airQ-export-") {
            try manager.removeItem(at: item)
        }
    }
}
