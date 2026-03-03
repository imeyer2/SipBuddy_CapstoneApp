//
//  RootView.swift
//  SipBuddy
//
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

    // Pager state
    @State private var pageIndex: Int = 0 // 0: home, 1: incidents
    @State private var dragOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 1
    @State private var isPagerDragging: Bool = false
    @State private var didLockDirection: Bool = false


    var body: some View {
        ZStack {
            // Oura-style gradient background
            GradientBackground()
            
            VStack(spacing: 0) {
                // Custom horizontal pager (no early snap, only settles on release)
                GeometryReader { geo in
                    let width = geo.size.width
                    Color.clear
                        .allowsHitTesting(false)
                        .onAppear { containerWidth = max(width, 1) }
                        .onChange(of: geo.size.width) { _, newW in containerWidth = max(newW, 1) }

                    HStack(spacing: 0) {
                        HomeView().frame(width: width)
                        IncidentsView().frame(width: width)
                    }
                    .contentShape(Rectangle()) // Ensure entire area responds to gestures
                    .offset(x: -CGFloat(pageIndex) * width + dragOffset)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .local)
                            .onChanged { value in
                                if app.isPagingDisabled { 
                                    Log.d("[Pager] Dragging disabled by app.isPagingDisabled")
                                    return
                                }

                                let tx = value.translation.width
                                let ty = value.translation.height
                                let absX = abs(tx)
                                let absY = abs(ty)

                                // Ultra lenient: almost always prefer horizontal
                                if !didLockDirection {
                                    // Lock horizontal immediately - just 3pt of any horizontal movement
                                    if absX > 3 {
                                        didLockDirection = true
                                        isPagerDragging = true
                                        Log.d("[Pager] Locked HORIZONTAL - absX=\(absX), absY=\(absY)")
                                    } else if absY > 40 && absX < 2 {
                                        // Only lock vertical if purely vertical with almost no horizontal
                                        didLockDirection = true
                                        isPagerDragging = false
                                        dragOffset = 0
                                        Log.d("[Pager] Locked VERTICAL (no paging) - absX=\(absX), absY=\(absY)")
                                        return
                                    } else {
                                        // Not enough info yet — don't update offset
                                        return
                                    }
                                }

                                guard isPagerDragging else { return }

                                var x = tx
                                // Edge resistance at bounds
                                if (pageIndex == 0 && x > 0) || (pageIndex == 1 && x < 0) {
                                    x *= 0.3
                                    Log.d("[Pager] Edge resistance applied - pageIndex=\(pageIndex), tx=\(tx), adjusted x=\(x)")
                                }
                                dragOffset = x
                            }
                            .onEnded { value in
                                Log.d("[Pager] Drag ended - translation.width=\(value.translation.width), isPagerDragging=\(isPagerDragging), didLockDirection=\(didLockDirection)")
                                defer { didLockDirection = false; isPagerDragging = false }

                                if app.isPagingDisabled {
                                    Log.d("[Pager] onEnded: paging disabled, resetting")
                                    dragOffset = 0
                                    return
                                }
                                guard isPagerDragging else {
                                    Log.d("[Pager] onEnded: wasn't paging, resetting")
                                    dragOffset = 0
                                    return
                                }

                                let width = max(containerWidth, 1)
                                let threshold = width * 0.08 // super easy to trigger
                                var next = pageIndex
                                Log.d("[Pager] Checking threshold: width=\(width), threshold=\(threshold), translation=\(value.translation.width)")
                                if value.translation.width < -threshold { next = min(1, pageIndex + 1) }
                                else if value.translation.width > threshold { next = max(0, pageIndex - 1) }
                                
                                Log.d("[Pager] Page change: \(pageIndex) -> \(next)")

                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    pageIndex = next
                                    dragOffset = 0
                                }
                                // Sync app.tab after settle
                                let newTab = indexToTab(next)
                                if newTab != app.tab { app.tab = newTab }
                            }
                    )
                }
                
                // Bottom tab bar
                bottomTabBar()
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
            telemetry.startModeSession(newMode: ModeWire.sleep)

        }
        .onReceive(NotificationCenter.default.publisher(for: .incidentCompleted)) { n in
            guard let id = n.userInfo?["id"] as? UUID else { return }
            handleIncidentCompleted(id: id)
        }
        
        // MARK: - BuddySystemPaylod
        .sheet(item: $store.pendingBuddyPayload) { payload in
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
        guard let inc = store.incidents.first(where: { $0.id == id }) else { return } // If the incident cannot be found just return

        // Always upload incident media to server (regardless of buddies)
        telemetry.uploadIncidentMedia(incident: inc)
        
        // If no buddies configured, skip the buddy notification logic
        guard !buddies.contacts.isEmpty else { return }

        // Message body
        var parts = ["Heads up: SipBuddy detected a possible incident."]
        parts.append(inc.placeName.map { "Location: \($0)" } ?? "Location: \(inc.formattedLocation)")
        parts.append("Time: \(inc.formattedDateTime)")
        let body = parts.joined(separator: " ")

        // Split recipients by per-contact delivery mode
        let autoSendNums = buddies.contacts.filter { $0.mode == .autoSend }.map { $0.phone }
        let askFirstNums = buddies.contacts.filter { $0.mode == .askFirst }.map { $0.phone }
        let webhookEnabled = buddies.autoSendViaServer
        let webhookURLString = buddies.webhookURL
        let framesPNG = inc.framesPNG // Capture for background thread
        
        // Build media file on background thread (GIF encoding is CPU-intensive)
            var mediaURL: URL? = nil
            var mediaUTI: String? = nil
            
            let imgs = framesPNG.compactMap { UIImage(data: $0) }
            if imgs.count > 1, let gif = GIFEncoder.makeGIF(from: imgs, fps: 30) {
                let p = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(id).gif")
                try? gif.write(to: p)
                mediaURL = p
                mediaUTI = "image/gif"
            } else if let first = framesPNG.first {
                let p = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(id).png")
                try? first.write(to: p)
                mediaURL = p
                mediaUTI = "public.jpeg"
            }
            
            // Auto-send path via webhook (if configured)
            if webhookEnabled,
               let url = URL(string: webhookURLString),
               !webhookURLString.isEmpty,
               !autoSendNums.isEmpty
            {
                BuddyWebhookSender.send(contacts: autoSendNums, body: body, mediaURL: mediaURL, mediaUTI: mediaUTI, to: url)
            }
            
            // Ask-first path → show toast on main thread
            if !askFirstNums.isEmpty {
                ThreadingManager.onMain { [app, store] in
                    app.bottomNotice = AppState.BottomNotice(
                        title: "Send to your Buddies?",
                        message: "Tap Send to notify selected contacts about this incident.",
                        actionTitle: "Send",
                        action: { [askFirstNums, body] in
                            store.pendingBuddyPayload = BuddyPayload(
                                recipients: askFirstNums,
                                body: body,
                                incidentID: id
                            )
                        }
                    )
                }
            }
        }
    }

    
    
    




// MARK: - Bottom Tab Bar
private extension RootView {
    @ViewBuilder
    func bottomTabBar() -> some View {
        HStack(spacing: 0) {
            tabBarButton(index: 0, title: "Home", systemImage: "house.fill")
            
            ZStack(alignment: .top) {
                tabBarButton(index: 1, title: "Incidents", systemImage: "exclamationmark.circle")
                if app.hasUnseenIncident && app.tab != .incidents {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                        .offset(y: 4)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.clear)
    }
    
    func tabBarButton(index: Int, title: String, systemImage: String) -> some View {
        let isActive = pageIndex == index
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                pageIndex = index
                dragOffset = 0
            }
            let newTab = indexToTab(index)
            if newTab != app.tab { app.tab = newTab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: isActive ? .semibold : .regular))
                Text(title)
                    .font(.caption2.weight(isActive ? .semibold : .regular))
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    func tabToIndex(_ tab: AppState.Tab) -> Int {
        switch tab { case .home: 0; case .incidents: 1 }
    }
    func indexToTab(_ idx: Int) -> AppState.Tab {
        switch idx { case 0: .home; default: .incidents }
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


