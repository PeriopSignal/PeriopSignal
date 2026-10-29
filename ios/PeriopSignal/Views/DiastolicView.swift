import SwiftUI

/// ASE diastolic function: the guideline's variables in, the grade and filling pressure out.
/// (The algorithm lands with the verified cutoffs.)
struct DiastolicView: View {
    var onOpen: (URL) -> Void

    var body: some View {
        ScrollView {
            Text("Loading the algorithm…").font(PS.sys(size: 14)).foregroundStyle(PS.fg3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(FeedBackground())
        .navigationTitle("ASE Diastolic Function")
        .navigationBarTitleDisplayMode(.inline)
    }
}
