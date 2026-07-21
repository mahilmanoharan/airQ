import Foundation

// MARK: - Pollen
public struct Pollen: Codable, Sendable {
    public let message: String
    public let lat, lng: Double
    public let data: [Datum]
}

// MARK: - Datum
public struct Datum: Codable, Sendable {
    public let timezone: String
    public let species: Species
    public let risk: Risk
    public let count: Count
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case timezone
        case species = "Species"
        case risk = "Risk"
        case count = "Count"
        case updatedAt
    }
}

// MARK: - Count
public struct Count: Codable, Sendable {
    public let grassPollen, treePollen, weedPollen: Int

    enum CodingKeys: String, CodingKey {
        case grassPollen = "grass_pollen"
        case treePollen = "tree_pollen"
        case weedPollen = "weed_pollen"
    }
}

// MARK: - Risk
public struct Risk: Codable, Sendable {
    public let grassPollen, treePollen, weedPollen: String

    enum CodingKeys: String, CodingKey {
        case grassPollen = "grass_pollen"
        case treePollen = "tree_pollen"
        case weedPollen = "weed_pollen"
    }
}

// MARK: - Species
public struct Species: Codable, Sendable {
    public let grass: Grass
    public let others: Int
    public let tree: Tree
    public let weed: Weed

    enum CodingKeys: String, CodingKey {
        case grass = "Grass"
        case others = "Others"
        case tree = "Tree"
        case weed = "Weed"
    }
}

// MARK: - Grass
public struct Grass: Codable, Sendable {
    public let grassPoaceae: Int

    enum CodingKeys: String, CodingKey {
        case grassPoaceae = "Grass / Poaceae"
    }
}

// MARK: - Tree
public struct Tree: Codable, Sendable {
    public let ash, birch, elm, maple: Int
    public let mulberry, oak, pine, poplar: Int

    enum CodingKeys: String, CodingKey {
        case ash = "Ash"
        case birch = "Birch"
        case elm = "Elm"
        case maple = "Maple"
        case mulberry = "Mulberry"
        case oak = "Oak"
        case pine = "Pine"
        case poplar = "Poplar / Cottonwood"
    }
}

// MARK: - Weed
public struct Weed: Codable, Sendable {
    public let ragweed: Int

    enum CodingKeys: String, CodingKey {
        case ragweed = "Ragweed"
    }
}
