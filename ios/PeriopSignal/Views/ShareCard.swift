import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// A post as a square-ish picture for Messages, Slack and social: headline, three take-home points,
/// the source line and a QR code to the deep dive. Rendered at 3x by ShareCardRenderer.
struct ShareCardView: View {
    var post: Post
    var qr: UIImage?
    static let width: CGFloat = 360

    // Fixed dark palette so the image looks the same whatever the phone's appearance.
    private let bg = Color(hex: "0A0E14")
    private let surface = Color(hex: "111722")
    private let fg = Color(hex: "ECF0F6")
    private let fg2 = Color(hex: "A9B3C2")
    private let fg3 = Color(hex: "717D8F")
    private let line = Color(hex: "2C3748")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LogoMark(size: 26, cornerRadius: 7)
                HStack(spacing: 5) {
                    Text("Periop").foregroundStyle(fg)
                    Text("Signal").foregroundStyle(PS.coral)
                }
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .kerning(-0.4)
                Spacer()
                if post.isLandmark {
                    Text("LANDMARK")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded)).kerning(0.5)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(PS.coral.opacity(0.18), in: Capsule())
                        .foregroundStyle(PS.coral)
                }
            }

            HStack(spacing: 5) {
                Text(post.journal).fontWeight(.semibold).foregroundStyle(fg)
                Text("·").foregroundStyle(fg3)
                Text(post.kind)
                Text("·").foregroundStyle(fg3)
                Text(PSDate.display(post.date, long: true))
                if !post.trialName.isEmpty {
                    Text("·").foregroundStyle(fg3)
                    Text(post.trialName).font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(fg2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(post.headline)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(fg)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(post.takeHome.prefix(3).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "diamond.fill").font(.system(size: 6)).foregroundStyle(PS.coral).padding(.top, 1)
                        Text(item).font(.system(size: 13.5)).foregroundStyle(fg).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(line, lineWidth: 1))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.takeHomeIsAuthors ? "Take-home points as stated by the authors." : "Take-home points from the post.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(fg2)
                    Text("Scan for the deep dive and the paper link. Confirm details against the paper before changing practice.")
                        .font(.system(size: 10.5)).foregroundStyle(fg3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("periopsignal.github.io/PeriopSignal")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(PS.coral)
                }
                Spacer(minLength: 0)
                if let qr {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 58, height: 58)
                        .padding(4)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(20)
        .frame(width: Self.width)
        .background(
            ZStack {
                bg
                LinearGradient(colors: [PS.coral.opacity(post.isLandmark ? 0.16 : 0.08), .clear], startPoint: .topLeading, endPoint: .center)
            }
        )
        .environment(\.colorScheme, .dark)
    }
}

enum ShareCardRenderer {
    /// QR code for the post's page on the site (black on white, crisp at 3x).
    static func qrImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    @MainActor
    static func render(_ post: Post) -> UIImage? {
        let view = ShareCardView(post: post, qr: qrImage(for: post.siteLink))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: ShareCardView.width, height: nil)
        return renderer.uiImage
    }
}

#Preview {
    ShareCardView(post: .sample, qr: ShareCardRenderer.qrImage(for: Post.sample.siteLink))
}
