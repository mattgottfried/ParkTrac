import SwiftUI
import SwiftData

struct RideDetailSheet: View {
    let ride: DisplayRide
    let theme: ParkTheme
    let parkGroup: ParkGroup
    var parkName: String = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var allRideLogs: [RideLog]
    @Query private var allAlerts: [RideAlert]

    @State private var showLogSheet = false
    @State private var showAlertSheet = false
    @State private var showBookReturnSheet = false
    @State private var showAddToPlanSheet = false
    @State private var showToast = false
    @State private var toastMessage = ""

    private var rideCount: Int {
        allRideLogs.filter { $0.rideId == ride.id }.count
    }

    private var badgeColor: Color {
        guard ride.isOperating else { return .gray }
        guard let minutes = ride.waitMinutes else { return .blue }
        if minutes < 30 { return .green }
        if minutes < 60 { return Color(red: 1, green: 0.75, blue: 0) }
        return .red
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Capsule()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)

                // Ride name + status
                VStack(spacing: 6) {
                    Text(ride.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(ride.statusDisplay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Wait time display
                if ride.isOperating, let minutes = ride.waitMinutes {
                    VStack(spacing: 2) {
                        Text("\(minutes)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeColor)
                        Text("minute wait")
                            .font(.headline)
                            .foregroundStyle(badgeColor.opacity(0.8))
                    }
                } else {
                    Image(systemName: ride.status == "DOWN"
                          ? "exclamationmark.triangle.fill"
                          : "xmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(ride.status == "DOWN" ? .orange : .gray)
                }

                Divider()

                // Ride info (height, thrill, type)
                if let info = rideMetadata[ride.name] {
                    rideInfoSection(info)
                        .padding(.horizontal)
                    Divider()
                }

                // Predictions / closure info
                RidePredictionView(ride: ride, parkGroup: parkGroup, parkName: parkName)
                    .padding(.horizontal)

                Divider()

                // Rode It! + Wish List section
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            showLogSheet = true
                        } label: {
                            Label("Rode It!", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button {
                            appState.toggleWish(ride.id)
                        } label: {
                            Image(systemName: appState.wishList.contains(ride.id) ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundStyle(appState.wishList.contains(ride.id) ? .yellow : .secondary)
                                .padding(10)
                                .background(Color(.systemFill), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if rideCount > 0 {
                        Text("You've ridden this \(rideCount) time\(rideCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Divider()

                // Wait Stopwatch section
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
                        toastMessage = "Saved! Posted: \(posted)m · Actual: \(actualMins)m"
                        withAnimation { showToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { showToast = false }
                        }
                    }
                )
                .padding(.horizontal)

                Divider()

                // Log Return Time section
                Button {
                    showBookReturnSheet = true
                } label: {
                    Label("Log Return Time", systemImage: "clock.badge.checkmark")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .padding(.horizontal)

                Button {
                    showAddToPlanSheet = true
                } label: {
                    Label("Add to My Day", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                .padding(.horizontal)

                Divider()

                // Alert section
                VStack(spacing: 10) {
                    let existingAlert = allAlerts.first(where: { $0.rideId == ride.id && $0.isActive })
                    if let alert = existingAlert {
                        HStack {
                            Label("Alert: ≤\(alert.thresholdMinutes) min", systemImage: "bell.fill")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            Spacer()
                            Button("Cancel") {
                                alert.isActive = false
                                try? context.save()
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Button {
                            showAlertSheet = true
                        } label: {
                            Label("Set Wait Alert", systemImage: "bell.badge")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)

                Button("Dismiss") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentColor)
                    .padding(.top, 4)
            }
            .padding()
        }
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
        .presentationDragIndicator(.hidden)
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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Ride Info Section

    @ViewBuilder
    private func rideInfoSection(_ info: RideInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ride Info")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                infoChip(
                    label: info.heightInches.map { "\($0)\" min height" } ?? "No height requirement",
                    systemImage: "ruler",
                    color: info.heightInches != nil ? .blue : .secondary
                )
                infoChip(
                    label: info.thrill.rawValue,
                    systemImage: info.thrill.systemImage,
                    color: info.thrill.color
                )
            }

            HStack(spacing: 10) {
                infoChip(
                    label: info.type.rawValue,
                    systemImage: info.type.systemImage,
                    color: .indigo
                )
                infoChip(
                    label: info.lightningLane ? "Lightning Lane" : "Standby Only",
                    systemImage: info.lightningLane ? "bolt.fill" : "person.2.fill",
                    color: info.lightningLane ? .yellow : .secondary
                )
            }
        }
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
            notes: notes
        )
        context.insert(log)
        try? context.save()

        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}
