//
//  RidingBoundaryMapCard.swift
//  epac
//

import CoreLocation
import MapKit
import SwiftUI

struct RidingBoundaryMapCard: View {
	let ridingName: String
	let party: Party
	let isCompact: Bool

	@State private var boundary: RidingBoundary?
	@State private var isLoading = false
	@State private var errorMessage: String?
	@State private var mapType: MKMapType = .standard
	@State private var showsUserLocation = false
	@State private var showingFullScreen = false
	@StateObject private var locationAuthorizer = RidingBoundaryLocationAuthorizer()

	init(ridingName: String, party: Party, isCompact: Bool = true) {
		self.ridingName = ridingName
		self.party = party
		self.isCompact = isCompact
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			header
			ZStack {
				if let boundary {
					RidingBoundaryMapView(
						boundary: boundary,
						mapType: mapType,
						showsUserLocation: showsUserLocation,
						tintColor: UIColor(Color.party(party))
					)
				} else if isLoading {
					ProgressView()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else {
					ContentUnavailableView(
						errorMessage ?? "Boundary unavailable",
						systemImage: "map",
						description: Text("Try again when the backend can reach the boundary data source.")
					)
				}
			}
			.frame(height: isCompact ? 220 : nil)
			.frame(maxWidth: .infinity, maxHeight: isCompact ? nil : .infinity)
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.overlay(alignment: .topTrailing) {
				controls
					.padding(8)
			}
			.overlay(alignment: .bottomLeading) {
				if isCompact, boundary != nil {
					Button {
						showingFullScreen = true
					} label: {
						Label("Expand map", systemImage: "arrow.up.left.and.arrow.down.right")
							.labelStyle(.iconOnly)
							.padding(9)
							.background(.regularMaterial)
							.clipShape(Circle())
					}
					.accessibilityLabel("Expand riding boundary map")
					.padding(8)
				}
			}
			DataSourceBadge(source: .electionsCanadaBoundaries())
		}
		.task(id: ridingName) {
			await loadBoundary()
		}
		.fullScreenCover(isPresented: $showingFullScreen) {
			NavigationStack {
				RidingBoundaryMapCard(ridingName: ridingName, party: party, isCompact: false)
					.ignoresSafeArea(edges: .bottom)
					.navigationTitle(ridingName)
					.navigationBarTitleDisplayMode(.inline)
					.toolbar {
						ToolbarItem(placement: .confirmationAction) {
							Button("Done") { showingFullScreen = false }
						}
					}
			}
		}
	}

	private var header: some View {
		HStack {
			Label("Riding boundary", systemImage: "map.fill")
				.font(.subheadline.weight(.semibold))
			Spacer()
			if let boundary {
				Text(boundary.representationOrder)
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var controls: some View {
		HStack(spacing: 8) {
			Picker("Map style", selection: $mapType) {
				Image(systemName: "map").tag(MKMapType.standard)
				Image(systemName: "globe.americas.fill").tag(MKMapType.hybrid)
			}
			.pickerStyle(.segmented)
			.frame(width: 92)
			Button {
				locationAuthorizer.requestWhenInUse()
				showsUserLocation = true
			} label: {
				Image(systemName: showsUserLocation ? "location.fill" : "location")
					.frame(width: 30, height: 30)
					.background(.regularMaterial)
					.clipShape(Circle())
			}
			.accessibilityLabel("Show my location")
		}
	}

	@MainActor
	private func loadBoundary() async {
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }
		do {
			boundary = try await RidingBoundaryService().boundary(for: ridingName)
		} catch RidingBoundaryServiceError.notFound {
			errorMessage = "Boundary not found"
		} catch {
			errorMessage = "Boundary unavailable"
		}
	}
}

struct RidingBoundaryMapView: UIViewRepresentable {
	let boundary: RidingBoundary
	let mapType: MKMapType
	let showsUserLocation: Bool
	let tintColor: UIColor

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator
		mapView.pointOfInterestFilter = .excludingAll
		mapView.isPitchEnabled = false
		return mapView
	}

	func updateUIView(_ mapView: MKMapView, context: Context) {
		context.coordinator.tintColor = tintColor
		mapView.mapType = mapType
		mapView.showsUserLocation = showsUserLocation
		mapView.removeOverlays(mapView.overlays)
		let overlays = boundary.geometry.polygons.compactMap(makePolygon)
		mapView.addOverlays(overlays)
		guard !overlays.isEmpty else { return }
		let rect = overlays.reduce(MKMapRect.null) { partial, overlay in
			partial.union(overlay.boundingMapRect)
		}
		mapView.setVisibleMapRect(
			rect,
			edgePadding: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
			animated: false
		)
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(tintColor: tintColor)
	}

	private func makePolygon(_ polygon: RidingBoundaryPolygon) -> MKPolygon? {
		guard let exterior = polygon.rings.first, exterior.count >= 3 else { return nil }
		let coordinates = exterior.map(CLLocationCoordinate2D.init)
		let interiorPolygons = polygon.rings.dropFirst().compactMap { ring -> MKPolygon? in
			guard ring.count >= 3 else { return nil }
			let coordinates = ring.map(CLLocationCoordinate2D.init)
			return MKPolygon(coordinates: coordinates, count: coordinates.count)
		}
		return MKPolygon(
			coordinates: coordinates,
			count: coordinates.count,
			interiorPolygons: interiorPolygons.isEmpty ? nil : interiorPolygons
		)
	}

	final class Coordinator: NSObject, MKMapViewDelegate {
		var tintColor: UIColor

		init(tintColor: UIColor) {
			self.tintColor = tintColor
		}

		func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
			guard let polygon = overlay as? MKPolygon else {
				return MKOverlayRenderer(overlay: overlay)
			}
			let renderer = MKPolygonRenderer(polygon: polygon)
			renderer.strokeColor = tintColor
			renderer.fillColor = tintColor.withAlphaComponent(0.18)
			renderer.lineWidth = 2
			return renderer
		}
	}
}

private final class RidingBoundaryLocationAuthorizer: NSObject, ObservableObject, CLLocationManagerDelegate {
	private let manager = CLLocationManager()

	override init() {
		super.init()
		manager.delegate = self
	}

	func requestWhenInUse() {
		switch manager.authorizationStatus {
		case .notDetermined:
			manager.requestWhenInUseAuthorization()
		case .authorizedAlways, .authorizedWhenInUse:
			manager.startUpdatingLocation()
		case .denied, .restricted:
			break
		@unknown default:
			break
		}
	}
}

private extension CLLocationCoordinate2D {
	init(_ coordinate: RidingBoundaryCoordinate) {
		self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
	}
}
