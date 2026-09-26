import SwiftUI

struct StarRatingView: View {
    let label: String
    @Binding var rating: Int

    var body: some View {
        // Side by side normally; the name goes above the stars when text is too large to fit
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(label).font(.subheadline)
                Spacer(minLength: 0)
                stars
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline)
                stars
            }
        }
        // VoiceOver: one adjustable control — swipe up/down to change the rating
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5 stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
    }

    private var stars: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.4))
                    .font(.title3)
                    .onTapGesture { rating = star }
            }
        }
    }
}

struct StarDisplayView: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                let filled = Double(star) <= rating
                let half = !filled && Double(star) - 0.5 <= rating
                Image(systemName: filled ? "star.fill" : (half ? "star.leadinghalf.filled" : "star"))
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%g of 5 stars", rating))
    }
}
