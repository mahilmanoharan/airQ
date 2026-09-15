/// Respiratory/allergy-relevant labels confirmed present on
/// `SNClassifierIdentifier.version1` via `SoundClassifierProbe` (chunk 0).
///
/// Two labels were explicitly checked for and do **not** exist on this
/// classifier: `wheeze` and `throat_clearing`. Detecting either would
/// require a custom-trained Core ML sound classifier, not the built-in one.
///
/// This is a scope decision (which labels we bother persisting), not a
/// confidence threshold — every occurrence of an allowlisted label is
/// persisted regardless of how low its confidence is; filtering by
/// confidence value happens only at read time, in `DetectionAnalysis`.
public enum RespiratoryLabels {
    public static let allowlist: Set<String> = [
        "cough",
        "sneeze",
        "breathing",
        "gasp",
        "hiccup",
        "sigh",
        "snoring",
        "nose_blowing",
    ]
}
