import SwiftUI

/// Where to go from the Reference tab's lists and search results.
enum RefRoute: Hashable {
    case quickref(String)
    case score(String)
    case peds
    case local
    case infusions
    case neuraxial
    case fasting
    case airway
    case valves
    case intervention
    case ponv
    case chamber
    case diastolic
    case acls
    case abg
    case obEmergency
    case regionalFinder
    case blocks
    case neuraxialGuide
    case folder(RefFolder)

    /// Stable string for favorites and links ("score:rcri", "quickref:asra-last", "peds").
    var key: String {
        switch self {
        case .quickref(let id): return "quickref:" + id
        case .score(let id): return "score:" + id
        case .peds: return "peds"
        case .local: return "local"
        case .infusions: return "infusions"
        case .neuraxial: return "neuraxial"
        case .fasting: return "fasting"
        case .airway: return "airway"
        case .valves: return "valves"
        case .intervention: return "intervention"
        case .ponv: return "ponv"
        case .chamber: return "chamber"
        case .diastolic: return "diastolic"
        case .acls: return "acls"
        case .abg: return "abg"
        case .obEmergency: return "ob"
        case .regionalFinder: return "regional-finder"
        case .blocks: return "blocks"
        case .neuraxialGuide: return "neuraxial-guide"
        case .folder(let f): return "folder:" + f.rawValue
        }
    }
    init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first ?? "" {
        case "quickref" where parts.count == 2: self = .quickref(parts[1])
        case "score" where parts.count == 2: self = .score(parts[1])
        case "peds": self = .peds
        case "local": self = .local
        case "infusions": self = .infusions
        case "neuraxial": self = .neuraxial
        case "fasting": self = .fasting
        case "airway": self = .airway
        case "valves": self = .valves
        case "intervention": self = .intervention
        case "ponv": self = .ponv
        case "chamber": self = .chamber
        case "diastolic": self = .diastolic
        case "acls": self = .acls
        case "abg": self = .abg
        case "ob": self = .obEmergency
        case "regional-finder": self = .regionalFinder
        case "blocks": self = .blocks
        case "neuraxial-guide": self = .neuraxialGuide
        case "folder" where parts.count == 2:
            guard let f = RefFolder(rawValue: parts[1]) else { return nil }
            self = .folder(f)
        default: return nil
        }
    }
}

/// The Reference tab's folders. Each tool lives in one folder.
enum RefFolder: String, CaseIterable, Identifiable, Hashable {
    case emergency, preoperative, generalAnesthesia, regional, cardiothoracic, medications, pediatrics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .emergency: return "Emergency"
        case .preoperative: return "Preoperative"
        case .generalAnesthesia: return "General Anesthesia"
        case .regional: return "Regional"
        case .cardiothoracic: return "Cardiothoracic"
        case .medications: return "Medications & Hematology"
        case .pediatrics: return "Pediatrics"
        }
    }
    var icon: String {
        switch self {
        case .emergency: return "bolt.heart"
        case .preoperative: return "checklist"
        case .generalAnesthesia: return "lungs"
        case .regional: return "syringe"
        case .cardiothoracic: return "heart"
        case .medications: return "ivfluid.bag"
        case .pediatrics: return "figure.child"
        }
    }
    var tint: Color {
        switch self {
        case .emergency: return PS.accent
        case .preoperative: return PS.accent2
        case .generalAnesthesia: return Topics.info("thoracic").fg
        case .regional: return Topics.info("regional").fg
        case .cardiothoracic: return Topics.info("cardiacSurgery").fg
        case .medications: return PS.green
        case .pediatrics: return Topics.info("pediatric").fg
        }
    }
    /// The tools in this folder, in display order.
    var items: [RefItem] {
        switch self {
        case .emergency: return [
            RefItem(route: .acls, icon: "waveform.path.ecg", title: "ACLS", blurb: "Code clock, checklists and doses as it runs"),
            RefItem(route: .obEmergency, icon: "figure.and.child.holdinghands", title: "OB Emergencies", blurb: "Arrest, hemorrhage and other obstetric crises"),
            RefItem(route: .quickref("asra-last"), icon: "cross.vial", title: "Local Anesthetic Toxicity", blurb: "Checklist with lipid doses for the weight"),
            RefItem(route: .quickref("mhaus-mh"), icon: "thermometer.high", title: "Malignant Hyperthermia", blurb: "Checklist with dantrolene for the weight"),
            RefItem(route: .airway, icon: "wind", title: "Difficult Airway", blurb: "Assessment in, plan and checklists out"),
        ]
        case .preoperative: return [
            RefItem(route: .score("rcri"), icon: "heart.text.square", title: "RCRI", blurb: "Cardiac risk for non-cardiac surgery"),
            RefItem(route: .score("ariscat"), icon: "lungs", title: "ARISCAT", blurb: "Postoperative pulmonary complications"),
            RefItem(route: .score("stopbang"), icon: "zzz", title: "STOP-Bang", blurb: "Sleep apnea screening"),
            RefItem(route: .fasting, icon: "cup.and.saucer", title: "Fasting", blurb: "Last intake in, earliest start out"),
        ]
        case .generalAnesthesia: return [
            RefItem(route: .abg, icon: "testtube.2", title: "ABG Interpretation", blurb: "Primary disorder, compensation, mixed disorders"),
            RefItem(route: .ponv, icon: "pills", title: "PONV", blurb: "Apfel score, how many agents, rescue"),
            RefItem(route: .score("aldrete"), icon: "bed.double", title: "Modified Aldrete", blurb: "Ready to leave recovery?"),
        ]
        case .regional: return [
            RefItem(route: .regionalFinder, icon: "figure.stand", title: "Regional Technique Finder", blurb: "Mark the operative area, get neuraxial and block options"),
            RefItem(route: .blocks, icon: "dot.radiowaves.left.and.right", title: "Peripheral Nerve Blocks", blurb: "Placement, ultrasound view and volumes by block"),
            RefItem(route: .neuraxialGuide, icon: "figure.flexibility", title: "Neuraxial Guide", blurb: "Level, technique and dose by procedure"),
            RefItem(route: .neuraxial, icon: "drop.triangle", title: "Blocks on Anticoagulants", blurb: "Drug and last dose in, earliest block out"),
            RefItem(route: .local, icon: "syringe", title: "Local Anesthetic Doses", blurb: "One agent or a mixture, with Exparel"),
        ]
        case .cardiothoracic: return [
            RefItem(route: .valves, icon: "waveform.path.ecg.rectangle", title: "ASE Valve Severity Grading", blurb: "Echo numbers in, ASE grade out"),
            RefItem(route: .intervention, icon: "heart.circle", title: "AHA/ACC Valve Intervention", blurb: "Repair or replace? Prompted questions"),
            RefItem(route: .chamber, icon: "ruler", title: "ASE Chamber Quantification", blurb: "Sizes and function against the ASE cutoffs"),
            RefItem(route: .diastolic, icon: "waveform", title: "ASE Diastolic Function", blurb: "Grade and filling pressure, step by step"),
        ]
        case .medications: return [
            RefItem(route: .infusions, icon: "ivfluid.bag", title: "Medications & Hematology", blurb: "Drips, single doses, blood products and factors"),
        ]
        case .pediatrics: return [
            RefItem(route: .peds, icon: "scalemass", title: "Pediatric Doses", blurb: "Doses, tube sizes, fluids and blood volume"),
        ]
        }
    }
    /// One line of contents for the folder row; a folder with one tool describes the tool instead.
    var summary: String { items.count == 1 ? items[0].blurb : items.map(\.title).joined(separator: " · ") }
    /// Where the folder row goes: straight to the tool when the folder holds only one.
    var route: RefRoute { items.count == 1 ? items[0].route : .folder(self) }
}

/// A star in the toolbar of every tool, to add it to the favorites at the top of the tab.
struct FavoriteToolbar: ViewModifier {
    @Environment(FavoritesStore.self) private var favorites
    var route: RefRoute
    func body(content: Content) -> some View {
        if case .folder = route {
            content
        } else {
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    let on = favorites.contains(route.key)
                    Button {
                        Haptics.light()
                        withAnimation(.snappy) { favorites.toggle(route.key) }
                    } label: { Image(systemName: on ? "star.fill" : "star") }
                    .accessibilityLabel(on ? "Remove from favorites" : "Add to favorites")
                }
            }
        }
    }
}

struct RefItem: Hashable, Identifiable {
    var route: RefRoute
    var icon: String
    var title: String
    var blurb: String
    var id: RefRoute { route }

    static var all: [RefItem] { RefFolder.allCases.flatMap(\.items) }
    static func item(for route: RefRoute) -> RefItem? { all.first { $0.route == route } }
    static func item(forKey key: String) -> RefItem? { RefRoute(key: key).flatMap { item(for: $0) } }
    /// The folder a tool lives in.
    static func folder(of route: RefRoute) -> RefFolder? { RefFolder.allCases.first { $0.items.contains { $0.route == route } } }
}

/// The Reference tab: five folders of calculators and condensed society references, with one search
/// across all of it and the feed.
struct ReferenceView: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @Environment(ReferenceStore.self) private var refs
    @Environment(Router.self) private var router
    @Environment(FavoritesStore.self) private var favorites
    @State private var path = NavigationPath()
    @State private var webLink: WebLink?
    @State private var query = ""
    @State private var ask: AskPrompt?
    /// Passes a child's weight and age from the pediatric calculator to the local anesthetic one, once.
    @State private var handoff = PatientHandoff()

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !trimmed.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if searching {
                        ReferenceSearchResults(query: trimmed, path: $path) { ask = AskPrompt(question: trimmed) }
                    } else {
                        if !favorites.keys.isEmpty { favoritesSection }
                        folders
                        Text("A reference aid for licensed clinicians: confirm against the source and your institution's protocols before acting. Not reviewed or cleared by the FDA.")
                            .font(PS.sys(size: 12)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(FeedBackground())
            .scrollContentBackground(.hidden)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Drug, score, society, procedure")
            .navigationTitle("Reference")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: RefRoute.self) { route in
                destination(route).modifier(FavoriteToolbar(route: route))
            }
            .navigationDestination(for: Post.self) { post in
                DeepDiveView(post: post, onOpenPaper: { webLink = WebLink(url: $0) })
            }
            .listenBar()
        }
        .environment(handoff)
        .fullScreenCover(item: $webLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .sheet(item: $ask) { prompt in
            AskView(question: prompt.question,
                    onOpenPost: { post in ask = nil; path.append(post) },
                    onOpenRef: { ref in ask = nil; path.append(RefRoute.quickref(ref.id)) })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear { consumePending() }
        .onChange(of: router.pendingRefRoute) { _, _ in consumePending() }
        .onChange(of: refs.quickrefs.count) { _, _ in consumePending() }
    }

    @ViewBuilder private func destination(_ route: RefRoute) -> some View {
        RefDestination(route: route, push: { path.append($0) }, openURL: { webLink = WebLink(url: $0) }, path: $path, handoff: handoff)
    }

    /// Opens a route requested from a link or launch argument once its content exists.
    private func consumePending() {
        guard let route = router.pendingRefRoute else { return }
        if case .quickref(let id) = route, refs.quickref(id) == nil { return }   // wait for the bundle
        router.pendingRefRoute = nil
        path = NavigationPath()
        path.append(route)
    }

    // MARK: Favorites

    private var favoritesSection: some View {
        let items = favorites.keys.compactMap { RefItem.item(forKey: $0) }
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Favorites").padding(.leading, 2)
            TileGrid(items: items) { item in
                CalculatorTile(icon: item.icon, title: item.title, blurb: item.blurb, starred: true) { path.append(item.route) }
                    .contextMenu { Button(role: .destructive) { favorites.toggle(item.route.key) } label: { Label("Remove from favorites", systemImage: "star.slash") } }
            }
        }
    }

    // MARK: Folders

    private var folders: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(RefFolder.allCases.enumerated()), id: \.element.id) { i, f in
                    Button { path.append(f.route) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: f.icon)
                                .font(PS.sys(size: 17, weight: .semibold))
                                .foregroundStyle(f.tint)
                                .frame(width: 40, height: 40)
                                .background(f.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.title).font(PS.serif(size: 17)).foregroundStyle(PS.fg)
                                Text(f.summary).font(PS.sys(size: 12)).foregroundStyle(PS.fg2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if f.items.count > 1 { Text("\(f.items.count)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3) }
                            Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < RefFolder.allCases.count - 1 { Hairline().padding(.leading, 70) }
                }
            }
            .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
            HStack(alignment: .firstTextBaseline) {
                Text("Calculators ask for what they need and give the answer; the condensed references cite their society document and link to it. Confirm against the source before acting.")
                    .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)
            if let updated = refs.bundle?.updated { Eyebrow(text: "Content reviewed \(PSDate.monthYear(updated))", size: 10).padding(.leading, 2) }
        }
    }
}

/// One folder: its tools as tiles. Long-press a tile to star it.
struct FolderView: View {
    @Environment(ReferenceStore.self) private var refs
    @Environment(FavoritesStore.self) private var favorites
    var folder: RefFolder
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TileGrid(items: folder.items) { item in
                    let on = favorites.contains(item.route.key)
                    CalculatorTile(icon: item.icon, title: item.title, blurb: item.blurb, starred: on) { path.append(item.route) }
                        .contextMenu {
                            Button { favorites.toggle(item.route.key) } label: { Label(on ? "Remove from favorites" : "Add to favorites", systemImage: on ? "star.slash" : "star") }
                        }
                }
                Text("Long-press a tool to add it to your favorites at the top of the tab; the star in each tool's toolbar does the same.")
                    .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                if folder == .emergency {
                    Text("ACLS starts its code clock when it opens. The checklists take the patient's weight at the top and work out the doses; the weight clears when you leave.")
                        .font(PS.sys(size: 12.5)).foregroundStyle(PS.fg3).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .background(FeedBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Two-column tiles; the tiles in a row share one height, so a wrapped title never leaves its
/// neighbour floating.
struct TileGrid<Item: Identifiable, Tile: View>: View {
    var items: [Item]
    @ViewBuilder var tile: (Item) -> Tile

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                GridRow {
                    tile(items[i])
                    if i + 1 < items.count {
                        tile(items[i + 1])
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }
}

struct CalculatorTile: View {
    var icon: String
    var title: String
    var blurb: String
    var starred = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(PS.sys(size: 17, weight: .semibold))
                        .foregroundStyle(PS.accent)
                    Spacer()
                    if starred { Image(systemName: "star.fill").font(PS.sys(size: 11)).foregroundStyle(PS.accent) }
                }
                .frame(height: 22)
                Text(title)
                    .font(PS.serif(size: 16.5))
                    .foregroundStyle(PS.fg)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(blurb)
                    .font(PS.sys(size: 12))
                    .foregroundStyle(PS.fg2)
                    .lineSpacing(1)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PS.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct QuickRefRow: View {
    var ref: QuickRef
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ref.title)
                        .font(PS.serif(size: 15.5))
                        .foregroundStyle(PS.fg)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if ref.isEmergency {
                            Eyebrow(text: "Emergency", color: PS.accent, size: 9.5)
                        } else {
                            Circle().fill(Topics.info(ref.topic ?? "general").fg).frame(width: 7, height: 7)
                        }
                        Text(ref.societyShort).fontWeight(.semibold)
                        if let y = ref.year {
                            Text("·").foregroundStyle(PS.fg3)
                            Text(String(y))
                        }
                    }
                    .font(PS.sys(size: 12))
                    .foregroundStyle(PS.fg2)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3).padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search across everything

/// A question handed to the Ask sheet.
struct AskPrompt: Identifiable {
    var question: String
    var id: String { question }
}

struct ReferenceSearchResults: View {
    @Environment(PostStore.self) private var store
    @Environment(ReadStore.self) private var read
    @Environment(ReferenceStore.self) private var refs
    var query: String
    @Binding var path: NavigationPath
    var onAsk: () -> Void = {}

    private var askAvailable: Bool { AskEngine.onDeviceAvailable || refs.askEndpoint != nil }

    private var q: String { query.lowercased() }

    /// Words that bring up each guided tool; the content it is built on is searched as well.
    static func keywords(for route: RefRoute) -> [String] {
        switch route {
        case .peds: return ["pediatric", "peds", "child", "weight", "dose", "dosing", "ett", "tube", "lma", "fluid", "blood volume", "mabl"]
        case .local: return ["local anesthetic", "local anaesthetic", "max dose", "maximum dose", "exparel", "liposomal", "mixture", "toxicity", "mg/kg"]
        case .infusions: return ["infusion", "drip", "pressor", "vasopressor", "inotrope", "vasodilator", "hemodynamic", "bolus", "mcg/kg/min", "hematolog", "coagulation", "factor", "pcc", "antifibrinolytic", "transfus", "blood product", "red cell", "rbc", "prbc", "ffp", "plasma", "platelet", "cryo", "sedation", "antiarrhythmic"]
        case .neuraxial: return ["anticoag", "neuraxial", "epidural", "spinal", "block", "heparin", "enoxaparin", "lmwh", "warfarin", "apixaban", "rivaroxaban", "edoxaban", "dabigatran", "doac", "fondaparinux", "clopidogrel", "prasugrel", "ticagrelor", "aspirin", "thrombolytic", "asra"]
        case .fasting: return ["npo", "fasting", "fast", "clear liquid", "breast milk", "formula", "meal", "gum", "aspiration"]
        case .airway: return ["airway", "intubat", "laryngoscop", "cricothyr", "cannot ventilate", "cicv", "awake", "videolaryngoscope", "supraglottic", "lma"]
        case .valves: return ["cardiothoracic", "cardiac", "valve", "valvular", "echo", "tee", "stenosis", "regurgitation", "aortic", "mitral", "tricuspid", "vena contracta", "eroa", "pisa", "gradient", "ase"]
        case .intervention: return ["cardiothoracic", "cardiac", "valve", "valvular", "stenosis", "regurgitation", "aortic", "mitral", "tricuspid", "tavi", "tavr", "savr", "avr", "teer", "mitraclip", "pmbc", "commissurotomy", "repair", "replacement", "prosthesis", "mechanical", "bioprosthe", "acc", "aha"]
        case .ponv: return ["ponv", "nausea", "vomiting", "antiemetic", "apfel", "ondansetron", "dexamethasone", "droperidol", "amisulpride", "aprepitant", "scopolamine", "palonosetron", "granisetron", "promethazine", "rescue", "prophylaxis"]
        case .chamber: return ["cardiothoracic", "cardiac", "echo", "tee", "ase", "chamber", "quantification", "dilated", "dilation", "lvidd", "lvedd", "lvesd", "lv size", "lv mass", "hypertrophy", "wall thickness", "rwt", "ejection fraction", "lvef", "la volume", "lavi", "atrial", "rv", "right ventricle", "tapse", "fac", "basal", "tricuspid annulus", "annulus", "aorta", "aortic root", "sinus", "sinuses of valsalva", "ivc", "ra pressure", "right atrium", "rvot", "strain", "rimp", "tei", "s prime"]
        case .diastolic: return ["cardiothoracic", "cardiac", "echo", "tee", "ase", "diastolic", "diastology", "dysfunction", "filling pressure", "lap", "e/e", "e/a", "tr velocity", "la strain", "lars", "pulmonary vein", "hfpef", "relaxation", "restrictive"]
        case .acls: return ["acls", "pals", "code", "code blue", "cardiac arrest", "arrest", "cpr", "resuscitation", "defibrillation", "defibrillator", "shock", "vf", "vt", "pea", "asystole", "epinephrine", "adrenaline", "amiodarone", "lidocaine", "bradycardia", "tachycardia", "atropine", "adenosine", "cardioversion", "pacing", "rosc", "post-arrest", "cals", "resternotomy", "cardiac surgery arrest", "anaphylaxis", "allergic reaction", "timer"]
        case .abg: return ["abg", "blood gas", "arterial blood gas", "acid", "base", "acid-base", "acidosis", "alkalosis", "acidemia", "alkalemia", "ph", "paco2", "pco2", "hco3", "bicarbonate", "compensation", "winter", "respiratory acidosis", "metabolic acidosis", "respiratory alkalosis", "metabolic alkalosis", "mixed disorder", "henderson"]
        case .obEmergency: return ["ob", "obstetric", "obstetrics", "pregnancy", "pregnant", "maternal", "labor", "labour", "cesarean", "caesarean", "c-section", "postpartum", "hemorrhage", "haemorrhage", "pph", "atony", "oxytocin", "carboprost", "methylergonovine", "misoprostol", "tranexamic", "amniotic fluid embolism", "afe", "eclampsia", "preeclampsia", "magnesium", "perimortem", "resuscitative hysterotomy", "uterine displacement", "high spinal", "total spinal", "stanford"]
        case .regionalFinder: return ["regional", "block", "nerve block", "neuraxial", "spinal", "epidural", "incision", "dermatome", "surgery site", "technique", "which block", "analgesia"]
        case .blocks: return ["regional", "block", "nerve block", "peripheral", "pnb", "nysora", "ultrasound", "interscalene", "supraclavicular", "infraclavicular", "axillary", "suprascapular", "cervical plexus", "femoral", "adductor", "saphenous", "sciatic", "popliteal", "ipack", "pericapsular", "peng", "fascia iliaca", "obturator", "lateral femoral cutaneous", "ankle", "tap", "transversus", "rectus sheath", "quadratus", "erector", "esp", "paravertebral", "pecs", "serratus", "parasternal", "ilioinguinal", "caudal", "wrist", "volume"]
        case .neuraxialGuide: return ["neuraxial", "spinal", "epidural", "cse", "combined spinal", "intrathecal", "bupivacaine", "chloroprocaine", "ropivacaine", "dermatome", "level", "t4", "t10", "saddle", "cesarean", "c-section", "laparotomy", "appendectomy", "hip", "knee", "hernia", "turp", "anal", "perianal", "hemorrhoid", "labor"]
        case .quickref, .score, .folder: return []
        }
    }

    private func matches(_ item: RefItem) -> Bool {
        switch item.route {
        case .quickref, .folder: return false          // quick references have their own list
        case .score(let id): return Scores.byID(id)?.searchText.contains(q) ?? false
        case .peds:
            guard let p = refs.peds else { return false }
            return wordsMatch(item.route) || p.drugs.contains { $0.name.lowercased().contains(q) }
        case .local:
            guard let p = refs.peds else { return false }
            return wordsMatch(item.route) || p.localAnesthetics.contains { $0.name.lowercased().contains(q) }
        case .infusions:
            guard let data = refs.bundle?.infusions else { return false }
            return wordsMatch(item.route) || data.groups.contains { g in g.drugs.contains { ($0.name + " " + $0.use + " " + ($0.role ?? "")).lowercased().contains(q) } }
        case .neuraxial, .fasting, .airway, .valves, .intervention, .ponv, .chamber, .diastolic, .acls, .abg, .regionalFinder, .neuraxialGuide, .obEmergency:
            return wordsMatch(item.route)
        case .blocks:
            guard let data = refs.bundle?.regional else { return wordsMatch(item.route) }
            return wordsMatch(item.route) || data.blocks.contains { $0.name.lowercased().contains(q) }
        }
    }
    private func wordsMatch(_ route: RefRoute) -> Bool {
        Self.keywords(for: route).contains { $0.contains(q) || q.contains($0) }
    }

    private var tools: [RefItem] { RefItem.all.filter(matches) }
    private var quickrefs: [QuickRef] { refs.quickrefs.filter { $0.searchText.contains(q) } }
    private var papers: [Post] {
        store.posts.filter { $0.searchText.contains(q) }
    }

    var body: some View {
        let nothing = tools.isEmpty && quickrefs.isEmpty && papers.isEmpty
        if nothing {
            VStack(spacing: 10) {
                ContentUnavailableView.search(text: query)
                AskRow(query: query, available: askAvailable, action: onAsk)
            }
            .padding(.top, 30)
        } else {
            if !tools.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Calculators and guides").padding(.leading, 2)
                    TileGrid(items: tools) { item in
                        CalculatorTile(icon: item.icon, title: item.title, blurb: item.blurb) { path.append(item.route) }
                    }
                }
            }
            if !quickrefs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Quick references").padding(.leading, 2)
                    VStack(spacing: 0) {
                        ForEach(Array(quickrefs.enumerated()), id: \.element.id) { i, ref in
                            QuickRefRow(ref: ref) { path.append(RefRoute.quickref(ref.id)) }
                            if i < quickrefs.count - 1 { Hairline().padding(.leading, 18) }
                        }
                    }
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
            }
            if !papers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow(text: "In the feed").padding(.leading, 2)
                        Spacer()
                        Text("\(papers.count)").font(PS.mono(size: 11, weight: .semibold)).foregroundStyle(PS.fg3)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(papers.prefix(25).enumerated()), id: \.element.id) { i, post in
                            GuidelineRow(post: post, isUnread: read.isUnread(post)) { path.append(post) }
                            if i < min(papers.count, 25) - 1 { Hairline().padding(.leading, 18) }
                        }
                    }
                    .background(PS.surface, in: RoundedRectangle(cornerRadius: PS.cardRadius, style: .continuous))
                }
            }
            AskRow(query: query, available: askAvailable, action: onAsk)
        }
    }
}

/// A guideline or paper row: headline, then journal · kind · date with the topic dot.
struct GuidelineRow: View {
    var post: Post
    var isUnread: Bool
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(post.headline)
                        .font(PS.serif(size: 15.5))
                        .foregroundStyle(PS.fg)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Circle().fill(Topics.info(post.primaryTopic).fg).frame(width: 7, height: 7)
                        Text(post.journal).fontWeight(.semibold)
                        Text("·").foregroundStyle(PS.fg3)
                        Text(post.kind)
                        Text("·").foregroundStyle(PS.fg3)
                        Text(PSDate.display(post.date, long: true))
                        if post.isLandmark { Eyebrow(text: "Landmark", color: PS.accent, size: 9.5) }
                        if isUnread { UnreadDot() }
                    }
                    .font(PS.sys(size: 12))
                    .foregroundStyle(PS.fg2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(PS.sys(size: 12, weight: .semibold)).foregroundStyle(PS.fg3).padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A Reference tool or card for a route: pushed from the Reference tab, and from My Patient for its prompts.
struct RefDestination: View {
    @Environment(ReferenceStore.self) private var refs
    var route: RefRoute
    var push: (RefRoute) -> Void
    var openURL: (URL) -> Void
    /// The Reference tab's path, for folders; nil elsewhere.
    var path: Binding<NavigationPath>?
    var handoff: PatientHandoff

    var body: some View {
                switch route {
                case .quickref(let id):
                    if let ref = refs.quickref(id) {
                        QuickRefView(ref: ref, onOpen: { openURL($0) })
                    } else {
                        ContentUnavailableView("Not available offline yet", systemImage: "wifi.slash", description: Text("This reference arrives with the next refresh."))
                    }
                case .score(let id):
                    if let def = Scores.byID(id) { ScoreCalculatorView(def: def, onOpen: { openURL($0) }, onOpenRef: { push(RefRoute.quickref($0)) }) }
                case .peds:
                    PedsCalculatorView(onOpen: { openURL($0) }, onOpenLocal: { w, y in
                        handoff.pass(weightKg: w, ageYears: y)
                        push(RefRoute.local)
                    })
                case .local:
                    LocalAnestheticView(onOpen: { openURL($0) })
                case .infusions:
                    InfusionsView(onOpen: { openURL($0) })
                case .neuraxial:
                    NeuraxialTimingView(onOpen: { openURL($0) }, onOpenTable: { push(RefRoute.quickref("asra-anticoagulation")) })
                case .fasting:
                    FastingView(onOpen: { openURL($0) }, onOpenCard: { push(RefRoute.quickref("asa-fasting")) })
                case .airway:
                    AirwayGuideView(onOpen: { openURL($0) }, onOpenCard: { push(RefRoute.quickref("asa-difficult-airway")) })
                case .valves:
                    ValveGraderView(onOpen: { openURL($0) }, onOpenTable: { push(RefRoute.quickref("ase-valve-severity")) })
                case .intervention:
                    ValveInterventionView(onOpen: { openURL($0) }, onOpenCard: { push(RefRoute.quickref("acc-aha-valve-intervention")) })
                case .ponv:
                    PONVView(onOpen: { openURL($0) }, onOpenCard: { push(RefRoute.quickref("ponv-consensus")) })
                case .chamber:
                    ChamberQuantView(onOpen: { openURL($0) })
                case .diastolic:
                    DiastolicView(onOpen: { openURL($0) })
                case .acls:
                    AclsView(onOpen: { openURL($0) })
                case .abg:
                    AbgView(onOpen: { openURL($0) })
                case .obEmergency:
                    ObEmergencyView(onOpen: { openURL($0) })
                case .regionalFinder:
                    RegionalFinderView(onOpen: { openURL($0) }, onOpenBlocks: { push(RefRoute.blocks) })
                case .blocks:
                    BlocksView(onOpen: { openURL($0) })
                case .neuraxialGuide:
                    NeuraxialGuideView(onOpen: { openURL($0) })
                case .folder(let f):
                    if let path { FolderView(folder: f, path: path) }
                }
    }
}
