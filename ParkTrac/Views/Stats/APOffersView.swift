import SwiftUI

struct APOffersView: View {
    @Environment(AppState.self) private var appState

    private var filteredOffers: [APOffer] {
        allAPOffers.filter { offer in
            offer.isUnlocked(disneyTier: appState.disneyPassTier, universalTier: appState.universalPassTier)
        }
    }

    private let dateKey: String = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }()

    private func isUsed(_ offer: APOffer) -> Bool {
        UserDefaults.standard.bool(forKey: "usedOffer-\(offer.id)-\(dateKey)")
    }
    private func setUsed(_ offer: APOffer, _ used: Bool) {
        UserDefaults.standard.set(used, forKey: "usedOffer-\(offer.id)-\(dateKey)")
    }

    var body: some View {
        List {
            if filteredOffers.isEmpty {
                ContentUnavailableView("No Offers", systemImage: "tag.slash", description: Text("Set your pass tiers in Settings to see available offers."))
            } else {
                ForEach(["Walt Disney World", "Universal Orlando"], id: \.self) { resort in
                    let resortOffers = filteredOffers.filter { $0.resort == resort }
                    if !resortOffers.isEmpty {
                        Section(resort) {
                            ForEach(resortOffers) { offer in
                                OfferRow(offer: offer, isUsed: isUsed(offer)) { used in
                                    setUsed(offer, used)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("AP Offers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OfferRow: View {
    let offer: APOffer
    let isUsed: Bool
    let onToggle: (Bool) -> Void
    @State private var used: Bool

    init(offer: APOffer, isUsed: Bool, onToggle: @escaping (Bool) -> Void) {
        self.offer = offer
        self.isUsed = isUsed
        self.onToggle = onToggle
        _used = State(initialValue: isUsed)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(offer.title).font(.subheadline.weight(.medium))
                    .strikethrough(used)
                    .foregroundStyle(used ? .secondary : .primary)
                Text(offer.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                used.toggle()
                onToggle(used)
            } label: {
                Image(systemName: used ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(used ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
