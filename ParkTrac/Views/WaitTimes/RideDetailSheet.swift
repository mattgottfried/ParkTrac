import SwiftUI
import SwiftData
import PhotosUI

struct RideDetailSheet: View {
    @ScaledMetric(relativeTo: .largeTitle) private var tileSize: CGFloat = 84
    @ScaledMetric(relativeTo: .largeTitle) private var tileNumberSize: CGFloat = 36
    let ride: DisplayRide
    let theme: ParkTheme
    let parkGroup: ParkGroup
    var parkName: String = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(WaitTimesViewModel.self) private var viewModel
    @Query private var allRideLogs: [RideLog]
    @Query private var allAlerts: [RideAlert]
    @Query(filter: #Predicate<PlanItem> { $0.kind == "aap" && !$0.isDone }) private var openAccessReturns: [PlanItem]

    @State private var showLogSheet = false
    @State private var showAlertSheet = false
    @State private var showBookReturnSheet = false
    @State private var showAddToPlanSheet = false
    @State private var showToast = false
    @State private var toastMessage = ""

    private var rideCount: Int {
        allRideLogs.filter { $0.rideId == ride.id }.count
    }

    /// A single rider line, or a similar ride with a much shorter wait right now — the two real
    /// ways to cut a long standby line without a return-time pass.
    private var alternateSuggestion: AlternateRideSuggestion.Kind? {
        let candidates = viewModel.allRides
            .filter { $0.parkId == ride.parkId && $0.id != ride.id }
            .map { (name: $0.name, waitMinutes: $0.waitMinutes, isOperating: $0.isOperating) }
        return AlternateRideSuggestion.suggest(
            rideName: ride.name, waitMinutes: ride.waitMinutes, isOperating: ride.isOperating,
            candidates: candidates, resort: parkGroup)
    }

    /// The suggested ride's live entry, so tapping it can open its own sheet
    private func alternateRide(named name: String) -> DisplayRide? {
        viewModel.allRides.first { $0.parkId == ride.parkId && $0.name == name }
    }

    /// Today's logged-but-unused DAS/AAP return for this ride, if any
    private var loggedAccessReturn: PlanItem? {
        openAccessReturns.first {
            $0.rideId == ride.id && Calendar.current.isDateInToday($0.date)
        }
    }

    private func accessPassSection(_ pass: AccessPass) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(pass.label, systemImage: "figure.roll")
                .font(.headline)
                .foregroundStyle(.teal)

            if let logged = loggedAccessReturn, let start = logged.llReturnStart {
                Label("Return logged for \(start.formatted(date: .omitted, time: .shortened))",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Text("You'll get a reminder when it opens. Mark it done in My Day after you ride.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Book now to return **\(pass.returnPhrase(postedWait: ride.waitMinutes))** (posted wait \(ride.waitMinutes ?? 0) min).")
                    .font(.subheadline)
                HStack(spacing: 10) {
                    Button {
                        pass.bookingApp.open()
                    } label: {
                        Label("Book in \(pass.bookingAppName)", systemImage: "arrow.up.forward.app")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        let start = ReturnTimeLogger.logAccessPassNow(
                            pass, rideId: ride.id, rideName: ride.name, parkName: parkName,
                            resort: parkGroup, postedWait: ride.waitMinutes, context: context)
                        flashToast("\(pass.label) logged — return \(start.formatted(date: .omitted, time: .shortened))")
                    } label: {
                        Label("I Booked It", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }
                Text("Got a different time from the \(pass.bookingAppName)? Use Return above to enter it exactly.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isMustDo: Bool { appState.wishList.contains(ride.id) }
    private var activeAlert: RideAlert? { allAlerts.first { $0.rideId == ride.id && $0.isActive } }
    private var goodTime: GoodTimeToRide.Deal? { GoodTimeService.shared.deal(for: ride.id) }

    /// How long you really wait vs the posted time, from your Rode It! stopwatch logs at this resort
    private var realWait: (minutes: Int, source: String)? {
        guard ride.isOperating, let posted = ride.waitMinutes, posted > 0 else { return nil }
        let timed = allRideLogs
            .filter { $0.resort == parkGroup.rawValue }
            .compactMap { log -> WaitReality.Timed? in
                guard let p = log.waitMinutes, let a = log.actualWaitMinutes else { return nil }
                return WaitReality.Timed(rideId: log.rideId, posted: p, actual: a)
            }
        guard let adjustment = WaitReality.adjustment(for: ride.id, timed: timed),
              adjustment.isWorthShowing(posted: posted) else { return nil }
        return (minutes: adjustment.actual(posted: posted), source: adjustment.sourceText)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                actionRow

                // Ride info chips (height, thrill, type, Lightning Lane)
                if let info = RideMetadata.info(for: ride.name, resort: parkGroup) {
                    rideInfoSection(info)
                }

                // A shorter way in when the standby line is long: single rider, or a similar
                // ride nearby that's currently much shorter
                if let alt = alternateSuggestion {
                    card { alternateSuggestionSection(alt) }
                }

                // DAS / AAP: book in the resort's app, then log the return here in one tap
                if let pass = AccessPass.held(at: parkGroup), ride.isOperating {
                    card { accessPassSection(pass) }
                }

                // Lightning Lane: next returns + notify-only watch
                if ride.multiPass != nil || ride.singlePass != nil {
                    card { LightningLaneSection(ride: ride, parkName: parkName, resort: parkGroup) }
                }

                // Alerts that are set (wait alert / reopen watch), or the offer to watch a closed ride
                if activeAlert != nil || !ride.isOperating || ReopenWatchService.shared.watch(for: ride.id) != nil {
                    card { alertsSection }
                }

                // Wait stopwatch
                card {
                    WaitStopwatchSection(
                        ride: ride,
                        parkName: parkName,
                        postedWait: ride.waitMinutes,
                        onSave: { actualMins, posted in
                            let log = RideLog(
                                rideId: ride.id,
                                rideName: ride.name,
                                parkId: ride.parkId,
                                parkName: parkName,
                                resort: parkGroup.rawValue,
                                riddenAt: .now,
                                waitMinutes: posted == 0 ? nil : posted,
                                actualWaitMinutes: actualMins,
                                notes: ""
                            )
                            context.insert(log)
                            flashToast("Saved! Posted: \(posted)m · Actual: \(actualMins)m")
                        }
                    )
                }

                // Predictions / closure info
                card { RidePredictionView(ride: ride, parkGroup: parkGroup, parkName: parkName, realWait: realWait?.minutes) }
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.orange, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: showToast) { _, shown in shown }
        .sensoryFeedback(.selection, trigger: isMustDo)
        .sheet(isPresented: $showLogSheet) {
            LogRideSheet(
                ride: ride,
                parkName: parkName,
                resort: parkGroup.rawValue
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAlertSheet) {
            SetAlertSheet(ride: ride)
        }
        .sheet(isPresented: $showBookReturnSheet) {
            BookReturnTimeSheet(ride: ride, parkGroup: parkGroup, parkName: parkName)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddToPlanSheet) {
            AddPlanItemView(resort: parkGroup.rawValue, prefillRide: ride, prefillPark: parkName)
        }
    }

    private func flashToast(_ message: String) {
        toastMessage = message
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showToast = false }
        }
    }

    // MARK: - Header

    /// Wait tile (same as the ride card) + name, park, status line and the Must-Do star.
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            WaitTile(ride: ride, size: tileSize, numberSize: tileNumberSize, unit: "min wait")

            VStack(alignment: .leading, spacing: 4) {
                Text(ride.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if !parkName.isEmpty {
                    Text(parkName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let status = statusLine {
                    Label(status.text, systemImage: status.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status.color)
                }
                if let real = realWait {
                    Label("You usually wait ~\(real.minutes) (posted \(ride.waitMinutes ?? 0)) · \(real.source)",
                          systemImage: "stopwatch")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.teal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if rideCount > 0 {
                    Label("Ridden \(rideCount) time\(rideCount == 1 ? "" : "s")", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                appState.toggleWish(ride.id)
            } label: {
                Image(systemName: isMustDo ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isMustDo ? .yellow : .secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMustDo ? "Remove from Must-Do" : "Add to Must-Do")
        }
    }

    /// Good-time deal, down, or closed — nothing extra for a normal operating ride.
    private var statusLine: (text: String, icon: String, color: Color)? {
        if let goodTime {
            return (text: "Good time to ride · \(goodTime.shortText)", icon: "arrow.down.circle.fill", color: .green)
        }
        if ride.status == "DOWN" { return (text: "Temporarily down", icon: "wrench.and.screwdriver", color: .orange) }
        if !ride.isOperating { return (text: ride.statusDisplay, icon: "moon.zzz", color: .secondary) }
        return nil
    }

    // MARK: - Quick actions

    /// Four big buttons, like Apple Maps: Rode It, Add to My Day, Wait Alert, Log Return.
    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton("Rode It!", icon: "checkmark.circle.fill", tint: .green, prominent: true) {
                showLogSheet = true
            }
            actionButton("My Day", icon: "calendar.badge.plus", tint: .purple) {
                showAddToPlanSheet = true
            }
            actionButton(activeAlert.map { "≤\($0.thresholdMinutes) min" } ?? "Alert",
                         icon: activeAlert == nil ? "bell.badge" : "bell.fill", tint: .blue) {
                showAlertSheet = true
            }
            actionButton("Return", icon: "clock.badge.checkmark", tint: .teal) {
                showBookReturnSheet = true
            }
        }
    }

    private func actionButton(_ title: String, icon: String, tint: Color, prominent: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(prominent ? tint : tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle(title))
    }

    private func accessibilityTitle(_ title: String) -> String {
        switch title {
        case "My Day": return "Add to My Day"
        case "Return": return "Log return time"
        case "Alert": return "Set wait alert"
        default: return title.hasPrefix("≤") ? "Wait alert set for \(title). Change it" : title
        }
    }

    // MARK: - Alerts

    @ViewBuilder
    private var alertsSection: some View {
        VStack(spacing: 10) {
            // Down or closed: offer a one-shot "tell me when it's back up"
            if !ride.isOperating || ReopenWatchService.shared.watch(for: ride.id) != nil {
                reopenWatchRow
            }
            if let alert = activeAlert {
                HStack {
                    Label("Alert when the wait is ≤\(alert.thresholdMinutes) min", systemImage: "bell.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button("Cancel") {
                        alert.isActive = false
                        try? context.save()
                        InstantAlertsService.shared.watchesChanged()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// A white rounded group on the grey sheet background.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Reopen watch

    @ViewBuilder
    private var reopenWatchRow: some View {
        if ReopenWatchService.shared.watch(for: ride.id) != nil {
            HStack {
                Label("Alert when it reopens", systemImage: "bell.badge.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Spacer()
                Button("Cancel") { ReopenWatchService.shared.remove(rideId: ride.id) }
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Button {
                ReopenWatchService.shared.add(ride: ride, parkName: parkName, resort: parkGroup)
            } label: {
                Label(ride.status == "DOWN" ? "Alert Me When It's Back Up" : "Alert Me When It Opens",
                      systemImage: "bell.and.waves.left.and.right")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(.green)
        }
    }

    // MARK: - Alternate suggestion (single rider / similar shorter ride)

    @ViewBuilder
    private func alternateSuggestionSection(_ kind: AlternateRideSuggestion.Kind) -> some View {
        switch kind {
        case .singleRider:
            Label("Single Rider line available here", systemImage: "person.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            Text("Usually much shorter — you won't sit with your group, but it's the fastest way on. Ask a team member for the entrance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .similarRide(let name, let waitMinutes):
            Label("Try instead: \(name)", systemImage: "arrow.triangle.swap")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            Text("Similar ride, only \(waitMinutes) min right now")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let alt = alternateRide(named: name) {
                Button("View \(name)") {
                    dismiss()
                    DeepLinkRouter.shared.open(.ride(id: alt.id))
                }
                .font(.caption.weight(.semibold))
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Ride Info Section

    @ViewBuilder
    private func rideInfoSection(_ info: RideInfo) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                infoChip(
                    label: heightLabel(info),
                    systemImage: "ruler",
                    color: info.hasHeightRequirement ? .blue : .secondary
                )
                infoChip(
                    label: info.thrill.rawValue,
                    systemImage: info.thrill.systemImage,
                    color: info.thrill.color
                )
                infoChip(
                    label: info.type.rawValue,
                    systemImage: info.type.systemImage,
                    color: .indigo
                )
                // Japan's return passes come from live data (shown above), not this table
                if parkGroup.isOrlando {
                    infoChip(
                        label: info.lightningLane ? "Lightning Lane" : "Standby Only",
                        systemImage: info.lightningLane ? "bolt.fill" : "person.2.fill",
                        color: info.lightningLane ? .yellow : .secondary
                    )
                }
                if RideMetadata.hasSingleRider(name: ride.name, resort: parkGroup) {
                    infoChip(label: "Single Rider", systemImage: "person.fill", color: .blue)
                }
                ForEach(RideSensory.flags(for: ride.name).labels, id: \.self) { label in
                    infoChip(label: label, systemImage: sensoryIcon(label), color: .secondary)
                }
            }
        }
    }

    private func sensoryIcon(_ label: String) -> String {
        switch label {
        case "Loud": return "speaker.wave.3.fill"
        case "Dark": return "moon.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    /// "102 cm min height" in Japan, "40\" min height" in Orlando, plus any maximum.
    private func heightLabel(_ info: RideInfo) -> String {
        let metric = RideMetadata.prefersMetric(parkGroup)
        guard let min = HeightFormat.short(info, metric: metric) else { return "No height requirement" }
        if metric, let max = info.maxHeightCm, let low = HeightFormat.centimetres(info) {
            return "\(low)–\(max) cm"
        }
        return "\(min) min height"
    }

    private func infoChip(label: String, systemImage: String, color: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Log Ride Confirmation Sheet

struct LogRideSheet: View {
    let ride: DisplayRide
    let parkName: String
    let resort: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var waitMinutes: Int? = nil
    @State private var notes = ""
    @State private var riddenAt = Date()
    @State private var saved = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoImage: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ride") {
                    LabeledContent("Attraction", value: ride.name)
                    LabeledContent("Park", value: parkName)
                    DatePicker("Date & Time", selection: $riddenAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Wait Time (optional)") {
                    if let current = ride.waitMinutes, ride.isOperating {
                        HStack {
                            Text("Current wait: \(current) min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Use this") { waitMinutes = current }
                                .font(.caption)
                        }
                    }

                    Stepper(
                        waitMinutes.map { "\($0) minutes" } ?? "Not recorded",
                        value: Binding(
                            get: { waitMinutes ?? 0 },
                            set: { waitMinutes = $0 == 0 ? nil : $0 }
                        ),
                        in: 0...300,
                        step: 5
                    )
                }

                Section("Notes (optional)") {
                    TextField("e.g. front row, single rider…", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("Photo (optional)") {
                    if let photoImage {
                        HStack {
                            Image(uiImage: photoImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Spacer()
                            Button("Remove", role: .destructive) {
                                self.photoImage = nil
                                photoItem = nil
                            }
                        }
                    } else {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Add a Photo", systemImage: "photo.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Log Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLog() }
                        .fontWeight(.semibold)
                }
            }
            .overlay {
                if saved {
                    VStack {
                        Spacer()
                        Label("Ride logged!", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.green, in: Capsule())
                            .padding(.bottom, 32)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: saved)
                }
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                photoImage = UIImage(data: data)
            }
        }
    }

    private func saveLog() {
        let log = RideLog(
            rideId: ride.id,
            rideName: ride.name,
            parkId: ride.parkId,
            parkName: parkName,
            resort: resort,
            riddenAt: riddenAt,
            waitMinutes: waitMinutes,
            notes: notes,
            photoData: photoImage?.jpegData(compressionQuality: 0.7)
        )
        context.insert(log)
        try? context.save()

        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}
