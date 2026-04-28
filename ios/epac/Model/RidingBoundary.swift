//
//  RidingBoundary.swift
//  epac
//

import Foundation

struct RidingBoundary: Decodable {
	let slug: String
	let name: String
	let externalID: String
	let representationOrder: String
	let source: String
	let sourceURL: URL
	let sourceNote: String
	let extent: [Double]
	let centroid: [Double]
	let geometry: RidingBoundaryGeometry

	enum CodingKeys: String, CodingKey {
		case slug
		case name
		case externalID = "external_id"
		case representationOrder = "representation_order"
		case source
		case sourceURL = "source_url"
		case sourceNote = "source_note"
		case extent
		case centroid
		case geometry
	}
}

struct RidingBoundaryGeometry: Decodable {
	let polygons: [RidingBoundaryPolygon]

	enum CodingKeys: String, CodingKey {
		case type
		case coordinates
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)
		switch type {
		case "Polygon":
			let coordinates = try container.decode([[[Double]]].self, forKey: .coordinates)
			polygons = [RidingBoundaryPolygon(rawRings: coordinates)]
		case "MultiPolygon":
			let coordinates = try container.decode([[[[Double]]]].self, forKey: .coordinates)
			polygons = coordinates.map(RidingBoundaryPolygon.init(rawRings:))
		default:
			throw DecodingError.dataCorruptedError(
				forKey: .type,
				in: container,
				debugDescription: "Unsupported boundary geometry type: \(type)"
			)
		}
	}
}

struct RidingBoundaryPolygon {
	let rings: [[RidingBoundaryCoordinate]]

	init(rawRings: [[[Double]]]) {
		rings = rawRings.map { ring in
			ring.compactMap { pair in
				guard pair.count >= 2 else { return nil }
				return RidingBoundaryCoordinate(latitude: pair[1], longitude: pair[0])
			}
		}
	}
}

struct RidingBoundaryCoordinate: Equatable {
	let latitude: Double
	let longitude: Double
}
