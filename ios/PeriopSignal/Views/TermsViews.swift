import SwiftUI

/// Shown once at first launch (and again when the terms change): what the app is, in four points, and an
/// acceptance button. Nothing else in the app opens until it is accepted.
struct TermsGateView: View {
    var onAccept: () -> Void
    @State private var showFull = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Before you start", color: PS.accent)
                        Text("Periop Signal").font(PS.sys(size: 28, weight: .bold, design: .serif)).foregroundStyle(PS.fg)
                    }
                    ForEach(Array(Terms.points.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: p.icon)
                                .font(PS.sys(size: 15, weight: .semibold))
                                .foregroundStyle(PS.accent)
                                .frame(width: 34, height: 34)
                                .background(PS.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(PS.sys(size: 15.5, weight: .semibold)).foregroundStyle(PS.fg)
                                Text(p.body).font(PS.sys(size: 13.5)).foregroundStyle(PS.fg2).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Button { showFull = true } label: { Label("Read the full terms and privacy", systemImage: "doc.text") }
                        .font(PS.sys(size: 14, weight: .semibold))
                        .buttonStyle(.borderless)
                        .tint(PS.accent)
                }
                .padding(.horizontal, 22)
                .padding(.top, 36)
                .padding(.bottom, 16)
            }
            VStack(spacing: 8) {
                Button { onAccept() } label: { Text(Terms.acceptLabel).frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(prominent: true))
                Text("You can read these again under More.").font(PS.sys(size: 12)).foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .background(PS.bg)
            .overlay(Rectangle().fill(PS.line).frame(height: 1), alignment: .top)
        }
        .background(PS.bg.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showFull) {
            NavigationStack {
                TermsView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showFull = false } } }
            }
            .presentationDragIndicator(.visible)
        }
    }
}

/// The full terms and the privacy notes (More → Terms and privacy).
struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                block("Terms of use", Terms.sections)
                block("Privacy", Terms.privacy)
                Text("Terms version " + Terms.version)
                    .font(PS.mono(size: 11, weight: .semibold))
                    .foregroundStyle(PS.fg3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 36)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Terms and Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ items: [(title: String, body: String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(it.title).font(PS.sys(size: 15, weight: .semibold)).foregroundStyle(PS.fg)
                        Text(it.body).font(PS.sys(size: 14)).foregroundStyle(PS.fg2).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
        }
    }
}
