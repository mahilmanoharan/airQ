import SoundAnalysis

/// Enumerates the built-in sound classifier's labels at runtime rather than
/// assuming any specific set exists on a given OS/deployment target.
public enum SoundClassifierProbe {
    public static func knownClassifications(
        for identifier: SNClassifierIdentifier = .version1
    ) throws -> [String] {
        try SNClassifySoundRequest(classifierIdentifier: identifier).knownClassifications
    }
}
