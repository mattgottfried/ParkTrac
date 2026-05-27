import SwiftUI

struct BucketProgressView: View {
    let visited: Int
    let total: Int
    let label: String
    let color: Color

    private var fraction: Double {
        total > 0 ? Double(visited) / Double(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Text("\(visited) / \(total)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(color)
                    if total > 0 {
                        Text("(\(Int((Double(visited) / Double(total) * 100).rounded()))%)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(color.opacity(0.7))
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * fraction, height: 8)
                        .animation(.spring(duration: 0.5), value: fraction)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
