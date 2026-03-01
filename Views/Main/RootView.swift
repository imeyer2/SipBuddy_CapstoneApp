//
//  RootView.swift
//  SipBuddy
//


import SwiftUI
import MessageUI // Needed for Buddy System messaging

struct RootView: View {
    
    
    @EnvironmentObject var app: AppState
    @EnvironmentObject var ble: BLEManager
    @StateObject private var location = LocationManager()
    
    
    // Telemetry setup
    @EnvironmentObject var telemetry: TelemetryManager

    
    // Variables required for the Buddy System
    @EnvironmentObject var store: IncidentStore
    @EnvironmentObject var buddies: BuddyStore
    @State private var pendingBuddyPayload: BuddyPayload? = nil

    // Pager state
    @State private var pageIndex: Int = 0 // 0: home, 1: incidents, 2: feedback
    @State private var dragOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 1
    @State private var headerItemFrames: [Int: CGRect] = [:]


    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with dynamic highlight
                ZStack(alignment: .leading) {
                    // Moving highlight (interpolated between current and neighbor while dragging)
                    if let highlight = interpolatedHighlightRect() {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: highlight.width, height: max(28, highlight.height))
                            .offset(x: highlight.minX, y: 0)
                            .animation(.linear(duration: 0.01), value: dragOffset)
                            .animation(.easeInOut(duration: 0.2), value: pageIndex)
                    }

                    HStack(spacing: 24) {
                        headerButton(index: 0, title: "Home", systemImage: "house.fill")
                        ZStack(alignment: .topTrailing) {
                            headerButton(index: 1, title: "Incidents", systemImage: "exclamationmark.circle")
                            if app.hasUnseenIncident && app.tab != .incidents {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                    .offset(x: 10, y: -10)
                            }
                        }
                        headerButton(index: 2, title: "Feedback", systemImage: "doc.text")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal)
                    .coordinateSpace(name: "header")
                    .onPreferenceChange(HeaderItemFrameKey.self) { frames in
                        headerItemFrames = frames
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Custom horizontal pager (no early snap, only settles on release)
                GeometryReader { geo in
                    let width = geo.size.width
                    Color.clear
                        .onAppear { containerWidth = max(width, 1) }
                        .onChange(of: geo.size.width) { _, newW in containerWidth = max(newW, 1) }

                    HStack(spacing: 0) {
                        HomeView().frame(width: width)
                        IncidentsView().frame(width: width)
                        FeedbackView().frame(width: width)
                    }
                    .offset(x: -CGFloat(pageIndex) * width + dragOffset)
                    .animation(dragOffset == 0 ? .easeInOut(duration: 0.25) : .none, value: pageIndex)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if app.isPagingDisabled { return }
                                // allow dragging within bounds with some resistance at edges
                                var x = value.translation.width
                                if (pageIndex == 0 && x > 0) || (pageIndex == 2 && x < 0) {
                                    x *= 0.3 // edge resistance
                                }
                                dragOffset = x
                            }
                            .onEnded { value in
                                if app.isPagingDisabled {
                                    dragOffset = 0
                                    return
                                }
                                let width = max(containerWidth, 1)
                                let threshold = width * 0.25
                                var next = pageIndex
                                if value.translation.width < -threshold { next = min(2, pageIndex + 1) }
                                else if value.translation.width > threshold { next = max(0, pageIndex - 1) }

                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    pageIndex = next
                                    dragOffset = 0
                                }
                                // Sync app.tab after settle
                                let newTab = indexToTab(next)
                                if newTab != app.tab { app.tab = newTab }
                            }
                    , including: app.isPagingDisabled ? .subviews : .gesture)
                }
            }
            if let notice = app.bottomNotice { BottomNoticeView(notice: notice) } // If bottom notice is defined/active make it pop up
        }
        .onAppear {
            ble.getLocation = { location.lastLocation }
            ble.resolvePlaceName = { loc, done in location.resolvePlaceName(for: loc, completion: done) }
            pageIndex = tabToIndex(app.tab)
        }
        
        // MARK: - Our custom notifications that we have extended to the Notification iOS package
        .onReceive(NotificationCenter.default.publisher(for: .didStartIncident)) { _ in
            withAnimation { app.hasUnseenIncident = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceDefaultSleep)) { _ in
            app.mode = .sleeping
            telemetry.startModeSession(newMode: .sleep)

        }
        .onReceive(NotificationCenter.default.publisher(for: .incidentCompleted)) { n in
            guard let id = n.userInfo?["id"] as? UUID else { return }
            handleIncidentCompleted(id: id)
        }
        
        // MARK: - BuddySystemPaylod
        .sheet(item: $pendingBuddyPayload) { payload in
            MessageComposerSheet(payload: payload)
        }
        // Keep pager in sync if tab changes externally
        .onChange(of: app.tab) { _, newVal in
            let idx = tabToIndex(newVal)
            if idx != pageIndex {
                withAnimation(.easeInOut(duration: 0.25)) { pageIndex = idx }
            }
        }
    }

    // Removed custom edge-swipe overlay to let native page-style dragging show the slide animation
    
    
    
    /// Handles the event when an incident has been marked as "completed".
    /// - Parameter id: The unique identifier (UUID) of the completed incident.
    private func handleIncidentCompleted(id: UUID) {
        guard !buddies.contacts.isEmpty else { return } // If there are no buddies just return
        guard let inc = store.incidents.first(where: { $0.id == id }) else { return } // If the incident cannot be found just return

        // Message body
        var parts = ["Heads up: SipBuddy detected a possible incident."]
        parts.append(inc.placeName.map { "Location: \($0)" } ?? "Location: \(inc.formattedLocation)")
        parts.append("Time: \(inc.formattedDateTime)")
        let body = parts.joined(separator: " ")

        // Build ONE media file path (GIF preferred, else first JPG), reuse for webhook + Messages
        var mediaURL: URL? = nil
        var mediaUTI: String? = nil
        do {
            let imgs = inc.framesPNG.compactMap { UIImage(data: $0) }
            if imgs.count > 1, let gif = GIFEncoder.makeGIF(from: imgs, fps: 30) {
                let p = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(id).gif")
                try? gif.write(to: p)
                mediaURL = p
                mediaUTI = "image/gif"
            } else if let first = inc.framesPNG.first {
                let p = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(id).png")
                try? first.write(to: p)
                mediaURL = p
                mediaUTI = "public.jpeg"
            }
        }
        
        

        // Split recipients by per-contact delivery mode
        let autoSendNums = buddies.contacts.filter { $0.mode == .autoSend }.map { $0.phone }
        let askFirstNums = buddies.contacts.filter { $0.mode == .askFirst }.map { $0.phone }

        // Auto-send path via webhook (if configured)
        if buddies.autoSendViaServer,
           let url = URL(string: buddies.webhookURL),
           !buddies.webhookURL.isEmpty,
           !autoSendNums.isEmpty
        {
            BuddyWebhookSender.send(contacts: autoSendNums, body: body, mediaURL: mediaURL, mediaUTI: mediaUTI, to: url)
        }

        // Ask-first path → show toast; action opens Messages sheet with those recipients
        if !askFirstNums.isEmpty {
            app.bottomNotice = AppState.BottomNotice(
                title: "Send to your Buddies?",
                message: "Tap Send to notify selected contacts about this incident.",
                actionTitle: "Send",
                action: { [askFirstNums, body] in
                    pendingBuddyPayload = BuddyPayload(
                        recipients: askFirstNums,
                        body: body,
                        incidentID: id
                    )
                }
            )
            // BottomNoticeView auto-dismisses after ~3s in your code; that’s your “toaster”. :contentReference[oaicite:5]{index=5}
        }
        
        
        
    
        // NEW: Upload clip to Azure + notify server
        telemetry.uploadIncidentMedia(incident: inc)
    }


    
    
    
}



// MARK: - Payload & Composer
struct BuddyPayload: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
    let incidentID: UUID
}

// MARK: - Header frames & helpers
private struct HeaderItemFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension RootView {
    func headerButton(index: Int, title: String, systemImage: String) -> some View {
        let isActive = pageIndex == index
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                pageIndex = index
                dragOffset = 0
            }
            let newTab = indexToTab(index)
            if newTab != app.tab { app.tab = newTab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .font(.subheadline.weight(isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeaderItemFrameKey.self,
                                       value: [index: proxy.frame(in: .named("header"))])
            }
        )
    }

    func tabToIndex(_ tab: AppState.Tab) -> Int {
        switch tab { case .home: 0; case .incidents: 1; case .feedback: 2 }
    }
    func indexToTab(_ idx: Int) -> AppState.Tab {
        switch idx { case 0: .home; case 1: .incidents; default: .feedback }
    }

    func interpolatedHighlightRect() -> CGRect? {
        // Need frames for current and neighbor
        guard containerWidth > 0 else { return nil }
        let current = pageIndex
        let progressRaw = -dragOffset / containerWidth
        let direction = progressRaw >= 0 ? 1 : -1
        let neighbor = min(max(current + direction, 0), 2)
        let progress = min(1, max(0, abs(progressRaw)))

        guard let f0 = headerItemFrames[current] else { return nil }
        let f1 = headerItemFrames[neighbor] ?? f0

        func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
        let x = lerp(f0.minX, f1.minX, progress)
        let w = lerp(f0.width, f1.width, progress)
        let h = max(f0.height, f1.height)
        return CGRect(x: x, y: f0.minY, width: w, height: h)
    }
}

struct MessageComposerSheet: UIViewControllerRepresentable {
    @EnvironmentObject var store: IncidentStore
    let payload: BuddyPayload

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.recipients = payload.recipients
        vc.body = payload.body

        // Build media: GIF if multiple frames, else first JPEG
        if let inc = store.incidents.first(where: { $0.id == payload.incidentID }) {
            let imgs = inc.framesPNG.compactMap { UIImage(data: $0) }
            var url: URL? = nil
            var uti: String = "public.data"
            if imgs.count > 1, let gif = GIFEncoder.makeGIF(from: imgs, fps: 30) {
                let p = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(payload.incidentID).gif")
                if (try? gif.write(to: p)) != nil { url = p; uti = "image/gif" }
            } else if let first = inc.framesPNG.first {
                let p = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(payload.incidentID).png")
                if (try? first.write(to: p)) != nil { url = p; uti = "public.jpeg" }
            }
            if let url { vc.addAttachmentURL(url, withAlternateFilename: nil) /* iOS handles type via file ext */ }
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coord { Coord() }
    final class Coord: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
        }
    }
}






private struct BottomNoticeView: View {
    @EnvironmentObject var app: AppState
    let notice: AppState.BottomNotice

    @State private var dragOffsetY: CGFloat = 0

    var body: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title).bold()
                    Text(notice.message).font(.subheadline)
                }
                Spacer()
                Button(notice.actionTitle, action: notice.action)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .offset(y: max(0, dragOffsetY))
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        // only track downward drags
                        if value.translation.height > 0 {
                            dragOffsetY = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 80 {
                            withAnimation { app.bottomNotice = nil }
                        } else {
                            withAnimation { dragOffsetY = 0 }
                        }
                    }
            )
            .onAppear {
                // Auto-dismiss after 3 seconds if still the same notice
                let currentID = notice.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if app.bottomNotice?.id == currentID {
                        withAnimation { app.bottomNotice = nil }
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }
}






enum BuddyWebhookSender {
    static func send(contacts: [String], body: String, mediaURL: URL?, mediaUTI: String?, to endpoint: URL) {
        var json: [String: Any] = ["to": contacts, "text": body]
        if let mediaURL {
            if let data = try? Data(contentsOf: mediaURL) {
                json["media_base64"] = data.base64EncodedString()
                // crude mapping: only gif or jpeg in current flow
                json["media_type"] = (mediaUTI == "image/gif") ? "image/gif" : "image/jpeg"
            }
        }

        guard let payload = try? JSONSerialization.data(withJSONObject: json, options: []) else { return }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload

        URLSession.shared.dataTask(with: req) { _, _, _ in
            // you could add logging here if desired
        }.resume()
    }
}


