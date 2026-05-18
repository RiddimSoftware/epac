@testable import epac
import Foundation
import Testing

struct RidingBoundaryTests {
	@Test func decodesMultiPolygonBoundary() throws {
		let json = """
		{
		  "slug": "spadina-harbourfront",
		  "name": "Spadina-Harbourfront",
		  "external_id": "35100",
		  "representation_order": "2023",
		  "source": "Elections Canada - Federal Electoral District Boundary Files",
		  "source_url": "https://www.elections.ca/content.aspx?dir=cir%2FmapsCorner%2Fvector&document=index&lang=e&section=res",
		  "source_note": "Boundary geometry source note.",
		  "extent": [-79.41, 43.62, -79.36, 43.66],
		  "centroid": [-79.39, 43.64],
		  "geometry": {
		    "type": "MultiPolygon",
		    "coordinates": [[[[-79.41,43.62],[-79.40,43.63],[-79.36,43.66],[-79.41,43.62]]]]
		  }
		}
		"""

		let boundary = try JSONDecoder().decode(RidingBoundary.self, from: Data(json.utf8))

		#expect(boundary.externalID == "35100")
		#expect(boundary.geometry.polygons.count == 1)
		#expect(boundary.geometry.polygons[0].rings[0][0] == RidingBoundaryCoordinate(latitude: 43.62, longitude: -79.41))
	}

	@Test func slugNormalizesRidingPunctuation() {
		#expect(RidingBoundaryService.slug(for: "Scarborough Centre—Don Valley East") == "scarborough-centre-don-valley-east")
		#expect(RidingBoundaryService.slug(for: "Longueuil—Saint‑Hubert") == "longueuil-saint-hubert")
	}

	@Test func boundaryReadsBySlugArtifact() async throws {
		let json = """
		{
		  "slug": "spadina-harbourfront",
		  "name": "Spadina-Harbourfront",
		  "external_id": "35100",
		  "representation_order": "2023",
		  "source": "Elections Canada",
		  "source_url": "https://www.elections.ca/",
		  "source_note": "Boundary geometry source note.",
		  "extent": [-79.41, 43.62, -79.36, 43.66],
		  "centroid": [-79.39, 43.64],
		  "geometry": {
		    "type": "Polygon",
		    "coordinates": [[[-79.41,43.62],[-79.40,43.63],[-79.36,43.66],[-79.41,43.62]]]
		  }
		}
		"""
		let key = ArtifactKey("ridings/v1/by-slug/spadina-harbourfront.json")
		let artifacts = MockArtifactFetcher([key: json])

		let boundary = try await RidingBoundaryService(artifacts: artifacts).boundary(for: "Spadina-Harbourfront")

		#expect(boundary.slug == "spadina-harbourfront")
		#expect(artifacts.requestedKeys == [key])
	}
}
