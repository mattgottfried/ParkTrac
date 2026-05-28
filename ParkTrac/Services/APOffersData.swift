import Foundation

// MARK: - AP Offer Model

struct APOffer: Identifiable {
    let id: String
    let resort: String          // "Walt Disney World" or "Universal Orlando"
    let tier: String            // minimum tier required
    let title: String
    let detail: String
    let validMonths: [Int]      // 1–12, empty = year-round
}

// MARK: - All Offers

let allAPOffers: [APOffer] = [
    // Disney
    APOffer(id: "disney_photopass",   resort: "Walt Disney World",   tier: "Incredi-Pass",    title: "PhotoPass Memory Maker included",  detail: "Download unlimited photos and videos.",                                              validMonths: []),
    APOffer(id: "disney_parking",     resort: "Walt Disney World",   tier: "Sorcerer Pass",   title: "Free standard parking",            detail: "Show your AP at the toll plaza.",                                                    validMonths: []),
    APOffer(id: "disney_dining_15",   resort: "Walt Disney World",   tier: "Sorcerer Pass",   title: "15% dining discount",              detail: "At select table-service and quick-service locations. Show AP before ordering.",      validMonths: []),
    APOffer(id: "disney_merch_15",    resort: "Walt Disney World",   tier: "Sorcerer Pass",   title: "15% merchandise discount",         detail: "At most Disney-owned retail locations. Exclusions apply.",                           validMonths: []),
    APOffer(id: "disney_early_entry", resort: "Walt Disney World",   tier: "Pirate Pass",     title: "Early Theme Park Entry",           detail: "Enter any park 30 min before official open.",                                        validMonths: []),
    APOffer(id: "disney_springs_10",  resort: "Walt Disney World",   tier: "Pirate Pass",     title: "10% Disney Springs dining",        detail: "At select Disney Springs restaurants.",                                              validMonths: []),
    // Universal
    APOffer(id: "universal_parking",  resort: "Universal Orlando",   tier: "Premier Pass",    title: "Free self-parking",                detail: "Show your AP at parking garage.",                                                    validMonths: []),
    APOffer(id: "universal_epa",      resort: "Universal Orlando",   tier: "Power Pass",      title: "Early Park Admission",             detail: "Enter select parks 1 hour before official open.",                                    validMonths: []),
    APOffer(id: "universal_dining_15",resort: "Universal Orlando",   tier: "Premier Pass",    title: "15% dining discount",              detail: "At select Universal restaurants. Show AP before ordering.",                          validMonths: []),
    APOffer(id: "universal_merch_10", resort: "Universal Orlando",   tier: "Power Pass",      title: "10% merchandise discount",         detail: "At Universal-owned retail locations.",                                               validMonths: []),
    APOffer(id: "universal_ap_days",  resort: "Universal Orlando",   tier: "Power Pass",      title: "AP Appreciation Weekends",         detail: "Special discount weekends throughout the year.",                                     validMonths: [9, 10, 11]),
    APOffer(id: "universal_hhn",      resort: "Universal Orlando",   tier: "Premier Pass",    title: "Halloween Horror Nights discount", detail: "Discounted HHN event tickets.",                                                      validMonths: [9, 10]),
]

// MARK: - Tier Ordering Helpers

private let disneyTierOrder: [String] = [
    "None", "Pixie Dust Pass", "Pirate Pass", "Sorcerer Pass", "Incredi-Pass"
]

private let universalTierOrder: [String] = [
    "None", "Seasonal Pass", "Select Pass", "Power Pass", "Preferred Pass", "Premier Pass"
]

extension APOffer {
    /// True if the user's current tier meets or exceeds the minimum tier for this offer.
    func isUnlocked(disneyTier: DisneyPassTier, universalTier: UniversalPassTier) -> Bool {
        if resort == "Walt Disney World" {
            let userIndex = disneyTierOrder.firstIndex(of: disneyTier.rawValue) ?? 0
            let reqIndex  = disneyTierOrder.firstIndex(of: tier) ?? disneyTierOrder.count
            return userIndex >= reqIndex
        } else {
            let userIndex = universalTierOrder.firstIndex(of: universalTier.rawValue) ?? 0
            let reqIndex  = universalTierOrder.firstIndex(of: tier) ?? universalTierOrder.count
            return userIndex >= reqIndex
        }
    }

    /// True if the offer is valid this month (or year-round).
    var isValidThisMonth: Bool {
        validMonths.isEmpty || validMonths.contains(Calendar.current.component(.month, from: .now))
    }
}
