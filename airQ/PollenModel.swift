import Foundation

// MARK: - Pollen Response

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let pollen = try? JSONDecoder().decode(Pollen.self, from: jsonData)

import Foundation

// MARK: - Pollen
struct Pollen: Codable {
    let message: String
    let data: [Datum]
}

// MARK: - Datum
struct Datum: Codable {
    let count: Count
    let risk: Risk
    let species: Species
    let updatedAt: String
    let lat, lng: Double

    enum CodingKeys: String, CodingKey {
        case count = "Count"
        case risk = "Risk"
        case species = "Species"
        case updatedAt, lat, lng
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
    let tree: Tree
    let weed: Weed
    let grass: Grass

    enum CodingKeys: String, CodingKey {
        case tree = "Tree"
        case weed = "Weed"
        case grass = "Grass"
    }
}

// MARK: - Grass
struct Grass: Codable {
    let grass: Int

    enum CodingKeys: String, CodingKey {
        case grass = "Grass"
    }
}

// MARK: - Tree
struct Tree: Codable {
    let oak, pine: Int

    enum CodingKeys: String, CodingKey {
        case oak = "Oak"
        case pine = "Pine"
    }
}

// MARK: - Weed
struct Weed: Codable {
    let ragweed: Int

    enum CodingKeys: String, CodingKey {
        case ragweed = "Ragweed"
    }
}

