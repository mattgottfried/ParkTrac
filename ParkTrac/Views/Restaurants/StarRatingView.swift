import SwiftUI

struct StarRatingView: View {
    let label: String
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.subheadline)
                .frame(width: 50, alignment: .leading)
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
    }
}
