import SwiftUI
import PDFKit
import CoreLocation

/// Shows an airport diagram with current (or test) position. Pinch to zoom, drag to pan. Use test position in Settings when not at the airport.
struct AirportDiagramView: View {

    let diagram: AirportDiagramInfo
    /// When provided, overlay shows the same intent rows (icons, badges) as the ATC card. Otherwise falls back to taxiInstructionText.
    var transmission: Transmission? = nil
    var recognizer: ATCLiveRecognizer? = nil
    var taxiInstructionText: String? = nil
    @ObservedObject private var locationManager = LocationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var diagramImageSize: CGSize? = nil
    @State private var currentViewSize: CGSize = .zero
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var showSetStartingPointMessage = false

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0

    var body: some View {
        NavigationStack {
            GeometryReader { outer in
                ZStack(alignment: .topLeading) {
                    // Zoomable diagram + position dot
                    ZStack(alignment: .topLeading) {
                        diagramLayer
                        positionOverlay
                    }
                    .frame(width: outer.size.width, height: outer.size.height)
                    .scaleEffect(zoomScale)
                    .offset(panOffset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = lastZoomScale * value
                                    zoomScale = min(maxZoom, max(minZoom, zoomScale))
                                }
                                .onEnded { _ in
                                    lastZoomScale = zoomScale
                                },
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { value in
                                    lastPanOffset = panOffset
                                    let d = value.translation.width * value.translation.width + value.translation.height * value.translation.height
                                    if d < 100, diagramImageSize != nil {
                                        setStartingPointAt(viewX: value.startLocation.x, viewY: value.startLocation.y, viewSize: outer.size)
                                    }
                                }
                        )
                    )
                    .contentShape(Rectangle())
                    .clipped()

                    // Taxi/instruction overlay: upper left, same format as ATC card (icons, badges) or plain text fallback
                    if let t = transmission, let r = recognizer {
                        VStack(alignment: .leading, spacing: 0) {
                            TransmissionCard.intentRowsView(transmission: t, recognizer: r)
                                .padding(12)
                                .frame(maxWidth: 320, alignment: .leading)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 8)
                        .padding(.leading, 12)
                    } else if let text = taxiInstructionText, !text.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            taxiCallout(text: text)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 8)
                        .padding(.leading, 12)
                    }

                    // "Starting point set" toast
                    if showSetStartingPointMessage {
                        VStack {
                            Text("Starting point set")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Spacer()
                        }
                        .padding(.top, 60)
                    }
                }
                .frame(width: outer.size.width, height: outer.size.height)
                .onAppear { currentViewSize = outer.size }
                .onChange(of: outer.size) { _, new in currentViewSize = new }
            }
            .navigationTitle("\(diagram.airportId) Diagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Button(action: zoomToCurrentPosition) {
                            Image(systemName: "location.fill")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Zoom to current position")
                        Button(action: resetZoomAndPan) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Reset zoom")
                    }
                }
            }
            .onAppear {
                locationManager.requestWhenInUseAuthorization()
                locationManager.startUpdatingLocation()
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
        }
    }

    private var diagramLayer: some View {
        GeometryReader { geo in
            if let image = loadDiagramImage() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onAppear { diagramImageSize = image.size }
            } else {
                placeholderDiagram(size: geo.size)
            }
        }
    }

    private func loadDiagramImage() -> UIImage? {
        if diagram.isPDF {
            let url: URL? = diagram.localPDFURL ?? Bundle.main.url(forResource: diagram.assetName, withExtension: "pdf")
            guard let url = url,
                  let doc = PDFDocument(url: url),
                  let page = doc.page(at: 0) else { return nil }
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            return page.thumbnail(of: size, for: .mediaBox)
        }
        if let img = UIImage(named: diagram.assetName) { return img }
        if let url = Bundle.main.url(forResource: diagram.assetName, withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) { return img }
        return nil
    }

    private func placeholderDiagram(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Add \(diagram.assetName).pdf to the app bundle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .frame(width: size.width, height: size.height)
    }

    private var positionOverlay: some View {
        GeometryReader { geo in
            if let loc = locationManager.effectiveLocation, let imgSize = diagramImageSize, imgSize.width > 0, imgSize.height > 0 {
                let pt = pointInView(for: loc.coordinate, viewSize: geo.size, imageSize: imgSize)
                PositionMarkerView()
                    .position(x: pt.x, y: pt.y)
            }
        }
    }

    /// Convert lat/lon to view coordinates. Diagram is aspect-fit in view; position is within the diagram's rendered rect.
    private func pointInView(for coord: CLLocationCoordinate2D, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        let (originX, originY, contentWidth, contentHeight) = diagramContentRect(viewSize: viewSize, imageSize: imageSize)
        let b = diagram.bounds
        let lonNorm = (coord.longitude - b.minLon) / (b.maxLon - b.minLon)
        let latNorm = (coord.latitude - b.minLat) / (b.maxLat - b.minLat)
        let x = originX + lonNorm * contentWidth
        let y = originY + (1 - latNorm) * contentHeight
        return CGPoint(x: x, y: y)
    }

    /// Diagram's rendered rect (aspect-fit) within the view.
    private func diagramContentRect(viewSize: CGSize, imageSize: CGSize) -> (originX: CGFloat, originY: CGFloat, contentWidth: CGFloat, contentHeight: CGFloat) {
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let contentWidth = imageSize.width * scale
        let contentHeight = imageSize.height * scale
        let originX = (viewSize.width - contentWidth) / 2
        let originY = (viewSize.height - contentHeight) / 2
        return (originX, originY, contentWidth, contentHeight)
    }

    /// Convert tap (in view) to lat/lon using same transform as diagram.
    private func viewToCoordinate(viewX: CGFloat, viewY: CGFloat, viewSize: CGSize) -> CLLocationCoordinate2D? {
        guard let imgSize = diagramImageSize, imgSize.width > 0, imgSize.height > 0 else { return nil }
        let cx = (viewX - viewSize.width / 2 - panOffset.width) / zoomScale + viewSize.width / 2
        let cy = (viewY - viewSize.height / 2 - panOffset.height) / zoomScale + viewSize.height / 2
        let (originX, originY, contentWidth, contentHeight) = diagramContentRect(viewSize: viewSize, imageSize: imgSize)
        guard contentWidth > 0, contentHeight > 0 else { return nil }
        let lonNorm = (cx - originX) / contentWidth
        let latNorm = 1 - (cy - originY) / contentHeight
        let b = diagram.bounds
        let lat = b.minLat + latNorm * (b.maxLat - b.minLat)
        let lon = b.minLon + lonNorm * (b.maxLon - b.minLon)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Convert tap (in view) to content coords, then to lat/lon; update test position and show toast.
    private func setStartingPointAt(viewX: CGFloat, viewY: CGFloat, viewSize: CGSize) {
        guard let coord = viewToCoordinate(viewX: viewX, viewY: viewY, viewSize: viewSize) else { return }
        locationManager.useTestPosition = true
        locationManager.testLat = coord.latitude
        locationManager.testLon = coord.longitude
        showSetStartingPointMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSetStartingPointMessage = false
        }
    }

    /// Taxi instruction text as a semi-transparent card overlay (upper left).
    private func taxiCallout(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: 320, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
    }

    private func resetZoomAndPan() {
        lastZoomScale = 1.0
        lastPanOffset = .zero
        withAnimation(.easeOut(duration: 0.25)) {
            zoomScale = 1.0
            panOffset = .zero
        }
    }

    /// Center the diagram on current position and zoom in to 2×.
    private func zoomToCurrentPosition() {
        guard let loc = locationManager.effectiveLocation,
              let imgSize = diagramImageSize,
              imgSize.width > 0, imgSize.height > 0,
              currentViewSize.width > 0, currentViewSize.height > 0 else { return }
        let pt = pointInView(for: loc.coordinate, viewSize: currentViewSize, imageSize: imgSize)
        let targetZoom: CGFloat = 2.0
        lastZoomScale = targetZoom
        lastPanOffset = CGSize(
            width: (currentViewSize.width / 2 - pt.x) * targetZoom,
            height: (currentViewSize.height / 2 - pt.y) * targetZoom
        )
        withAnimation(.easeOut(duration: 0.25)) {
            zoomScale = targetZoom
            panOffset = lastPanOffset
        }
    }
}

// MARK: - Blue "you are here" marker on the diagram with pulse/glow
private struct PositionMarkerView: View {
    @State private var pulseScale: CGFloat = 0.7
    @State private var pulseOpacity: Double = 0.5

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .strokeBorder(Color.blue.opacity(0.6), lineWidth: 2)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
            // Inner pulse ring
            Circle()
                .strokeBorder(Color.blue.opacity(0.35), lineWidth: 1.5)
                .scaleEffect(pulseScale * 0.85)
                .opacity(pulseOpacity * 0.9)
            // Center dot: small for precision, white stroke + glow so it stays visible
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
                .overlay { Circle().stroke(Color.white, lineWidth: 2) }
                .shadow(color: Color.blue.opacity(0.5), radius: 3, x: 0, y: 0)
        }
        .frame(width: 56, height: 56)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.5
                pulseOpacity = 0.06
            }
        }
    }
}
