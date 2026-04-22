import Foundation

// MARK: - Pollen
struct Pollen: Codable {
    let message: String
    let lat, lng: Double
    let data: [Datum]
}

// MARK: - Datum
struct Datum: Codable {
    let timezone: String
    let species: Species
    let risk: Risk
    let count: Count
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case timezone
        case species = "Species"
        case risk = "Risk"
        case count = "Count"
        case updatedAt
    }
}

// MARK: - Count
struct Count: Codable {
    let grassPollen, treePollen, weedPollen: Int

    enum CodingKeys: String, CodingKey {
        case grassPollen = "grass_pollen"
        case treePollen = "tree_pollen"
        case weedPollen = "weed_pollen"
    }
}

// MARK: - Risk
struct Risk: Codable {
    let grassPollen, treePollen, weedPollen: String

    enum CodingKeys: String, CodingKey {
        case grassPollen = "grass_pollen"
        case treePollen = "tree_pollen"
        case weedPollen = "weed_pollen"
    }
}

// MARK: - Species
struct Species: Codable {
    let grass: Grass
    let others: Int
    let tree: Tree
    let weed: Weed

    enum CodingKeys: String, CodingKey {
        case grass = "Grass"
        case others = "Others"
        case tree = "Tree"
        case weed = "Weed"
    }
}

// MARK: - Grass
struct Grass: Codable {
    let grassPoaceae: Int

    enum CodingKeys: String, CodingKey {
        case grassPoaceae = "Grass / Poaceae"
    }
}

// MARK: - Tree
struct Tree: Codable {
    let ash, birch, elm, maple: Int
    let mulberry, oak, pine, poplar: Int

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
struct Weed: Codable {
    let ragweed: Int

    enum CodingKeys: String, CodingKey {
        case ragweed = "Ragweed"
    }
}


