import XCTest
@testable import PeriopSignal

/// 1.9 (Ben): home medications from a large list, read several to a line; allergies as items with their severity; a
/// larger drip list read by spaces too. The flag of each drug class is checked on several drugs and brands: a wrong flag
/// is a clinical error.
final class MedicationCatalog19Tests: XCTestCase {
    private func flags(_ name: String) -> Set<String> { MedicationCatalog.flags(forName: name) }
    private func meds(_ line: String) -> [String] { MedicationCatalog.parse(line).map(\.text) }
    private func ids(_ line: String) -> [String?] { MedicationCatalog.parse(line).map(\.catalogID) }

    // MARK: The list

    func testEveryRowReadsAndEveryFlagIsKnown() {
        XCTAssertEqual(MedicationCatalog.entries.count, MedicationData.rows.count, "every row has five fields")
        XCTAssertGreaterThanOrEqual(MedicationCatalog.entries.count, 400)
        XCTAssertEqual(Set(MedicationCatalog.entries.map(\.id)).count, MedicationCatalog.entries.count, "ids are unique")
        let known = Set(PatientCatalog.medFlags.map(\.id))
        for e in MedicationCatalog.entries {
            XCTAssertTrue(e.flags.isSubset(of: known), e.id + ": \(e.flags.subtracting(known))")
            XCTAssertFalse(e.drugClass.isEmpty, e.id)
            XCTAssertEqual(e.aliases, e.aliases.map { $0.lowercased() }, e.id + ": aliases are lowercase")
        }
        // Every flag is raised by some drug.
        for f in known { XCTAssertTrue(MedicationCatalog.entries.contains { $0.flags.contains(f) }, f) }
    }

    /// No name or alias finds two drugs: each finds its own entry.
    func testEachNameFindsItsOwnEntry() {
        for e in MedicationCatalog.entries {
            for form in [e.name] + e.aliases {
                XCTAssertEqual(MedicationCatalog.entry(named: form)?.id, e.id, "“\(form)” of \(e.id)")
            }
        }
    }

    func testDoseAndTimingWordsAreNotDrugs() {
        for w in MedicationCatalog.noise.union(MedicationCatalog.leadNoise) {
            XCTAssertNil(MedicationCatalog.entry(named: w), w)
        }
        XCTAssertTrue(MedicationCatalog.parse("daily prn mg bid").isEmpty)
    }

    // MARK: Flags, class by class (generics and brands)

    func testFlagTable() {
        let table: [String: [String]] = [
            "anticoagulant": ["warfarin", "Coumadin", "Jantoven", "apixaban", "Eliquis", "rivaroxaban", "Xarelto", "edoxaban", "Savaysa",
                              "dabigatran", "Pradaxa", "enoxaparin", "Lovenox", "dalteparin", "Fragmin", "fondaparinux", "Arixtra",
                              "heparin", "SQ heparin", "DOAC", "LMWH"],
            "p2y12": ["clopidogrel", "Plavix", "prasugrel", "Effient", "ticagrelor", "Brilinta", "ticlopidine"],
            "aspirin": ["aspirin", "ASA", "baby aspirin", "Ecotrin", "Aggrenox", "aspirin/dipyridamole", "Yosprala", "Excedrin",
                        "Fiorinal", "Percodan"],
            "insulin": ["insulin", "insulin glargine", "Lantus", "Basaglar", "Toujeo", "Semglee", "Levemir", "Tresiba", "NPH",
                        "Humulin N", "Novolin R", "regular insulin", "Humulin R U-500", "Humalog", "Admelog", "Lyumjev", "Novolog",
                        "Fiasp", "Apidra", "Afrezza", "Humulin 70/30", "Novolog Mix 70/30", "Humalog Mix 75/25", "insulin pump",
                        "Xultophy", "Soliqua"],
            "glp1": ["semaglutide", "Ozempic", "Wegovy", "Rybelsus", "oral semaglutide", "tirzepatide", "Mounjaro", "Zepbound",
                     "liraglutide", "Victoza", "Saxenda", "dulaglutide", "Trulicity", "exenatide", "Byetta", "Bydureon BCise",
                     "lixisenatide", "Xultophy", "Soliqua", "GLP-1"],
            "sglt2": ["empagliflozin", "Jardiance", "dapagliflozin", "Farxiga", "canagliflozin", "Invokana", "ertugliflozin",
                      "Steglatro", "bexagliflozin", "Brenzavvy", "sotagliflozin", "Inpefa", "Glyxambi", "Synjardy", "Trijardy XR",
                      "Xigduo XR", "Qtern", "Invokamet", "Segluromet", "Steglujan"],
            "betablocker": ["metoprolol", "metoprolol tartrate", "Lopressor", "metoprolol succinate", "Toprol XL", "atenolol", "Tenormin",
                            "carvedilol", "Coreg", "bisoprolol", "propranolol", "Inderal LA", "labetalol", "nebivolol", "Bystolic",
                            "nadolol", "sotalol", "Betapace", "Tenoretic", "Ziac", "Byvalson"],
            "acei": ["lisinopril", "Zestril", "Prinivil", "enalapril", "Vasotec", "ramipril", "benazepril", "captopril", "quinapril",
                     "losartan", "Cozaar", "valsartan", "Diovan", "irbesartan", "olmesartan", "Benicar", "candesartan", "telmisartan",
                     "azilsartan", "sacubitril/valsartan", "Entresto", "Zestoretic", "Hyzaar", "Lotrel", "Exforge", "Azor", "Tribenzor",
                     "Edarbyclor", "Tarka", "Byvalson", "ACE inhibitor", "ARB"],
            "statin": ["atorvastatin", "Lipitor", "rosuvastatin", "Crestor", "simvastatin", "Zocor", "pravastatin", "lovastatin",
                       "fluvastatin", "pitavastatin", "Livalo", "Vytorin", "Roszet", "Caduet", "statin"],
            "steroid": ["prednisone", "prednisolone", "methylprednisolone", "Medrol", "dexamethasone", "Decadron", "hydrocortisone",
                        "Cortef", "fludrocortisone", "deflazacort", "Entocort EC", "Uceris", "steroids"],
            "opioid": ["oxycodone", "OxyContin", "Percocet", "Norco", "Vicodin", "hydrocodone", "morphine", "MS Contin", "hydromorphone",
                       "Dilaudid", "fentanyl patch", "Duragesic", "tramadol", "Ultram", "Ultracet", "tapentadol", "Nucynta", "methadone",
                       "buprenorphine", "Subutex", "Belbuca", "Butrans", "Sublocade", "Suboxone", "Zubsolv", "codeine", "Tylenol #3",
                       "meperidine", "butorphanol", "kratom", "Percodan"],
            "maoi": ["phenelzine", "Nardil", "tranylcypromine", "Parnate", "isocarboxazid", "Marplan", "selegiline", "Eldepryl", "Emsam",
                     "rasagiline", "Azilect", "safinamide", "Xadago", "linezolid", "Zyvox", "methylene blue", "ProvayBlue"],
        ]
        for (flag, names) in table {
            XCTAssertNotNil(PatientCatalog.medFlags.first { $0.id == flag }, flag)
            for n in names {
                XCTAssertNotNil(MedicationCatalog.entry(named: n), n + " is in the list")
                XCTAssertTrue(flags(n).contains(flag), n + " → " + flag + ", got \(flags(n))")
            }
        }
    }

    /// The flags a drug must not raise: antagonists are not opioids, an antiplatelet is not a P2Y12 inhibitor unless it is
    /// one, a mineralocorticoid antagonist or a renin inhibitor is not an ACE inhibitor or ARB, eye drops and inhaled
    /// steroids are not systemic.
    func testFlagsThatMustNotBeRaised() {
        let none: [String: String] = [
            "naltrexone": "opioid", "Vivitrol": "opioid", "Contrave": "opioid", "Lybalvi": "opioid", "naloxone": "opioid",
            "Narcan": "opioid", "methylnaltrexone": "opioid", "Movantik": "opioid", "loperamide": "opioid", "Lomotil": "opioid",
            "cilostazol": "p2y12", "dipyridamole": "p2y12", "vorapaxar": "p2y12", "Aggrenox": "p2y12",
            "salsalate": "aspirin", "Pepto-Bismol": "aspirin", "diflunisal": "aspirin", "celecoxib": "aspirin",
            "spironolactone": "acei", "eplerenone": "acei", "finerenone": "acei", "aliskiren": "acei", "amlodipine": "acei",
            "timolol": "betablocker", "Cosopt": "betablocker",
            "fluticasone": "steroid", "Flonase": "steroid", "Advair": "steroid", "Symbicort": "steroid", "budesonide": "steroid",
            "Pulmicort": "steroid", "hydrocortisone cream": "steroid", "triamcinolone": "steroid", "clobetasol": "steroid",
            "tedizolid": "maoi", "Uribel": "maoi", "sertraline": "maoi",
            "metformin": "insulin", "sitagliptin": "glp1", "Januvia": "glp1", "pramlintide": "insulin",
            "ezetimibe": "statin", "Repatha": "statin", "fenofibrate": "statin",
        ]
        for (name, flag) in none {
            XCTAssertNotNil(MedicationCatalog.entry(named: name), name)
            XCTAssertFalse(flags(name).contains(flag), name + " must not raise " + flag)
        }
        // Classes that say so.
        XCTAssertTrue(MedicationCatalog.entry(named: "naltrexone")?.drugClass.contains("antagonist") == true)
        XCTAssertTrue(MedicationCatalog.entry(named: "tirzepatide")?.drugClass.contains("GIP and GLP-1") == true)
        XCTAssertTrue(MedicationCatalog.entry(named: "linezolid")?.drugClass.contains("MAO") == true)
        XCTAssertEqual(flags("Xultophy"), ["insulin", "glp1"])
        XCTAssertEqual(flags("Percodan"), ["opioid", "aspirin"])
        XCTAssertEqual(flags("Aggrenox"), ["aspirin"])
        XCTAssertEqual(flags("Byvalson"), ["betablocker", "acei"])
        XCTAssertEqual(flags("Tylenol"), [], "acetaminophen alone")
        XCTAssertEqual(flags("not a drug"), [])
    }

    func testFlagsOfAList() {
        let list = MedicationCatalog.parse("Eliquis 5 bid, Mounjaro 5 weekly, metoprolol 25, Jardiance 10, foobarazine")
        XCTAssertEqual(MedicationCatalog.flags(for: list), ["anticoagulant", "glp1", "betablocker", "sglt2"])
        // A typed item whose name is one the list knows exactly counts too.
        XCTAssertEqual(MedicationCatalog.flags(for: [PatientMed(name: "Plavix", dose: "75")]), ["p2y12"])
        XCTAssertEqual(MedicationCatalog.flags(for: [PatientMed(name: "something else")]), [])
    }

    // MARK: Reading a line

    func testCommasAndDoses() {
        XCTAssertEqual(meds("metoprolol 25 mg bid, lisinopril 10"), ["Metoprolol 25 mg bid", "Lisinopril 10"])
        XCTAssertEqual(ids("metoprolol 25 mg bid, lisinopril 10"), ["metoprolol", "lisinopril"])
        XCTAssertEqual(meds("Metoprolol, lisinopril, atorvastatin, insulin glargine, aspirin"),
                       ["Metoprolol", "Lisinopril", "Atorvastatin", "Insulin glargine", "Aspirin"])
        XCTAssertEqual(meds("metformin 1,000 mg bid; glipizide 5"), ["Metformin 1,000 mg bid", "Glipizide 5"], "a thousands comma is no break")
        XCTAssertEqual(meds("Home meds: metoprolol 25 mg BID, atorvastatin 40 mg, apixaban 5 mg BID (held 3 days)."),
                       ["Metoprolol 25 mg BID", "Atorvastatin 40 mg", "Apixaban 5 mg BID (held 3 days)"])
        XCTAssertEqual(meds("lantus 20 units qhs and humalog sliding scale"), ["Insulin glargine 20 units qhs", "Insulin lispro sliding scale"])
        XCTAssertEqual(meds("metoprolol 25\nlisinopril 10"), ["Metoprolol 25", "Lisinopril 10"])
    }

    func testSpacesBetweenDrugs() {
        XCTAssertEqual(meds("metoprolol lisinopril atorvastatin"), ["Metoprolol", "Lisinopril", "Atorvastatin"])
        XCTAssertEqual(meds("aspirin 81 atorvastatin 40 at night"), ["Aspirin 81", "Atorvastatin 40 at night"])
        XCTAssertEqual(meds("Eliquis 5 bid Plavix 75 daily"), ["Apixaban 5 bid", "Clopidogrel 75 daily"])
    }

    func testNamesOfSeveralWordsAreReadWhole() {
        XCTAssertEqual(meds("insulin glargine 30 units"), ["Insulin glargine 30 units"])
        XCTAssertEqual(meds("Toprol XL 50 daily"), ["Metoprolol succinate 50 daily"])
        XCTAssertEqual(meds("insulin 10 units qhs"), ["Insulin 10 units qhs"], "insulin, type not named")
        XCTAssertEqual(meds("Humulin R U-500 50 units"), ["Insulin regular U-500 50 units"])
        XCTAssertEqual(meds("Tylenol #3 1 tab q6h prn"), ["Acetaminophen/codeine 1 tab q6h prn"])
        XCTAssertEqual(meds("Tylenol 650 mg q6h"), ["Acetaminophen 650 mg q6h"])
        XCTAssertEqual(meds("carbidopa/levodopa 25/100 tid"), ["Carbidopa/levodopa 25/100 tid"])
        XCTAssertEqual(meds("sacubitril/valsartan 24/26 bid"), ["Sacubitril/valsartan 24/26 bid"])
        XCTAssertEqual(meds("lisinopril hctz 20/25"), ["Lisinopril/hydrochlorothiazide 20/25"], "the combination pill")
        XCTAssertEqual(meds("St. John's wort, ginkgo, fish oil 1 g"), ["St John's wort", "Ginkgo biloba", "Fish oil 1 g"])
        XCTAssertEqual(meds("Rybelsus 7 mg daily"), ["Semaglutide, oral 7 mg daily"])
    }

    /// A brand reads as its generic; the catalog id keeps which entry it was.
    func testBrandsReadAsGenerics() {
        let r = MedicationCatalog.parse("Eliquis 5 mg bid, Mounjaro 7.5 weekly, Entresto 49/51 bid")
        XCTAssertEqual(r.map(\.name), ["Apixaban", "Tirzepatide", "Sacubitril/valsartan"])
        XCTAssertEqual(r.map(\.catalogID), ["apixaban", "tirzepatide", "sacubitril-valsartan"])
        XCTAssertEqual(meds("metoprolol (Toprol XL) 50 mg daily"), ["Metoprolol succinate 50 mg daily"], "the brand in parentheses is the same drug")
        XCTAssertEqual(meds("apixaban (Eliquis) 5 mg bid"), ["Apixaban 5 mg bid"])
        XCTAssertEqual(meds("MÉTOPROLOL 25"), ["Metoprolol 25"], "case and accents")
    }

    func testUnknownWords() {
        let r = MedicationCatalog.parse("foobarazine 10 mg daily, metoprolol")
        XCTAssertEqual(r.map(\.text), ["Foobarazine 10 mg daily", "Metoprolol"])
        XCTAssertNil(r[0].catalogID)
        XCTAssertEqual(meds("metoprolol 25 bid xyzolol 10"), ["Metoprolol 25 bid", "Xyzolol 10"], "a drug's ending after a dose")
        XCTAssertEqual(meds("aspirin 81 mg enteric coated daily"), ["Aspirin 81 mg enteric coated daily"], "dose words stay with their drug")
        XCTAssertEqual(meds("Vitamin K2 100 mcg"), ["Vitamin K2 100 mcg"])
        XCTAssertEqual(meds("2 puffs albuterol q4h prn"), ["Albuterol 2 puffs q4h prn"], "a dose written first")
        XCTAssertTrue(meds("daily, prn, 10 mg").isEmpty, "no drug name, no item")
    }

    func testTheWordBeingTypedWaitsForTheTypeahead() {
        XCTAssertEqual(MedicationCatalog.reading("metoprolol 25, foob").map(\.med.text), ["Metoprolol 25"])
        XCTAssertEqual(MedicationCatalog.reading("metoprolol 25, foob ").map(\.med.text), ["Metoprolol 25", "Foob"])
        XCTAssertEqual(MedicationCatalog.reading("metoprolol 25, lisinopril").map(\.med.text), ["Metoprolol 25", "Lisinopril"], "a known name shows")
    }

    // MARK: Search and the type-ahead

    func testSearch() {
        XCTAssertEqual(MedicationCatalog.search("eli").first?.id, "apixaban", "brand → generic")
        XCTAssertEqual(MedicationCatalog.hits("eli").first?.matched, "eliquis")
        XCTAssertEqual(Array(MedicationCatalog.search("met").prefix(2).map(\.id)), ["metformin", "metoprolol"], "the most prescribed first")
        XCTAssertEqual(MedicationCatalog.search("ins gla").first?.id, "insulin-glargine", "word by word")
        XCTAssertEqual(MedicationCatalog.search("TOPROL").first?.id, "metoprolol-succinate")
        XCTAssertEqual(MedicationCatalog.search("glargine").first?.id, "insulin-glargine", "a word inside the name")
        XCTAssertEqual(MedicationCatalog.search("tirz").first?.id, "tirzepatide")
        XCTAssertEqual(MedicationCatalog.search("mét").first?.id, "metformin", "accents ignored")
        XCTAssertTrue(MedicationCatalog.search("").isEmpty)
        XCTAssertTrue(MedicationCatalog.search("zzzz").isEmpty)
        XCTAssertLessThanOrEqual(MedicationCatalog.search("a", limit: 5).count, 5)
    }

    func testTypeahead() {
        let gla = MedicationCatalog.typeahead("metoprolol 25, insulin gla")
        XCTAssertEqual(gla.first?.hit.entry.id, "insulin-glargine")
        XCTAssertEqual(gla.first?.completing("metoprolol 25, insulin gla"), "metoprolol 25, Insulin glargine ")
        let meto = MedicationCatalog.typeahead("lisinopril meto")
        XCTAssertTrue(meto.contains { $0.hit.entry.id == "metoprolol" })
        XCTAssertEqual(meto.first { $0.hit.entry.id == "metoprolol" }?.completing("lisinopril meto"), "lisinopril Metoprolol ")
        XCTAssertTrue(MedicationCatalog.typeahead("metoprolol 25 mg b").isEmpty, "a dose word on its way")
        XCTAssertTrue(MedicationCatalog.typeahead("metoprolol 25 mg bi").isEmpty)
        XCTAssertTrue(MedicationCatalog.typeahead("metoprolol ").isEmpty, "a space: nothing being typed")
        XCTAssertTrue(MedicationCatalog.typeahead("Eliquis").isEmpty, "a whole name and nothing more")
        XCTAssertEqual(MedicationCatalog.typeahead("ozem").first?.completing("ozem"), "Semaglutide ")
    }

    // MARK: Adding to the list

    func testAddingUpdatesTheSameDrug() {
        var list = [PatientMed(name: "Metoprolol", dose: "25 mg bid", catalogID: "metoprolol"), PatientMed(name: "aspirin")]
        let items = MedicationCatalog.parse("metoprolol 50 bid, ASA 81, Eliquis 5 bid")
        XCTAssertEqual(MedicationCatalog.status(items[0], in: list), .replaces("25 mg bid"))
        XCTAssertEqual(MedicationCatalog.status(items[1], in: list), .new, "aspirin listed without a dose: the dose is new")
        XCTAssertEqual(MedicationCatalog.status(items[2], in: list), .new)
        MedicationCatalog.apply(items, to: &list)
        XCTAssertEqual(list.map(\.text), ["Metoprolol 50 bid", "aspirin 81", "Apixaban 5 bid"])
        XCTAssertEqual(list[1].catalogID, "aspirin", "the typed item gets its entry")
        XCTAssertEqual(MedicationCatalog.status(PatientMed(name: "Metoprolol", catalogID: "metoprolol"), in: list), .recorded, "no dose typed")
        MedicationCatalog.apply(MedicationCatalog.parse("metoprolol"), to: &list)
        XCTAssertEqual(list[0].dose, "50 bid", "a drug typed without a dose keeps its dose")
    }

    // MARK: Allergies

    private func allergies(_ line: String) -> [String] { AllergyCatalog.parse(line).map(\.text) }

    func testAllergyLine() {
        let r = AllergyCatalog.parse("PCN - rash, sulfa (hives), latex anaphylaxis")
        XCTAssertEqual(r.map(\.name), ["Penicillin", "Sulfa drugs", "Latex"])
        XCTAssertEqual(r.map(\.reaction), ["rash", "hives", ""])
        XCTAssertEqual(r.map(\.severity), [nil, nil, "anaphylaxis"], "hives and rash are reactions; a severity only when written")
        XCTAssertEqual(allergies("PCN mild rash, latex severe"), ["Penicillin (mild, rash)", "Latex (severe)"])
        XCTAssertEqual(allergies("PCN sulfa latex"), ["Penicillin", "Sulfa drugs", "Latex"], "spaces between allergens")
        XCTAssertEqual(allergies("allergic to penicillin, severe rash and hives"), ["Penicillin (severe, rash, hives)"])
        XCTAssertEqual(allergies("PCN - rash, hives"), ["Penicillin (rash, hives)"], "a reaction after a comma stays with its allergen")
        XCTAssertEqual(allergies("codeine (nausea, mild), strawberries hives"), ["Codeine (mild, nausea)", "Strawberries (hives)"])
        XCTAssertEqual(allergies("morphine - itching; contrast dye - anaphylaxis"), ["Morphine (itching)", "Iodinated contrast (anaphylaxis)"])
        XCTAssertEqual(allergies("eggs, soy, CHG"), ["Egg", "Soy", "Chlorhexidine"])
        XCTAssertEqual(allergies("blue dye anaphylaxis"), ["Isosulfan blue dye (anaphylaxis)"])
        XCTAssertEqual(allergies("Eliquis - bleeding"), ["Apixaban (bleeding)"], "a medication by its brand")
        XCTAssertTrue(AllergyCatalog.parse("NKDA").isEmpty)
        for s in ["NKDA", "nka", "No known allergies", "none"] { XCTAssertTrue(AllergyCatalog.isNone(s), s) }
        XCTAssertFalse(AllergyCatalog.isNone("PCN"))
    }

    func testAllergySearch() {
        XCTAssertEqual(AllergyCatalog.search("pcn").first?.name, "Penicillin")
        XCTAssertEqual(AllergyCatalog.search("lat").first?.name, "Latex", "the allergens that are not drugs first")
        XCTAssertEqual(AllergyCatalog.search("chlorhex").first?.name, "Chlorhexidine")
        XCTAssertEqual(AllergyCatalog.search("sulfa").first?.name, "Sulfa drugs")
        XCTAssertEqual(AllergyCatalog.search("eliq").first?.name, "Apixaban", "every medication")
        XCTAssertTrue(AllergyCatalog.typeahead("PCN - ra").isEmpty, "a reaction being typed")
        XCTAssertEqual(AllergyCatalog.typeahead("PCN, lat").first?.hit.entry.name, "Latex")
    }

    func testAddingAllergies() {
        var list = [PatientAllergy(name: "Penicillin")]
        let items = AllergyCatalog.parse("PCN - hives, latex anaphylaxis")
        XCTAssertEqual(AllergyCatalog.status(items[0], in: list), .new, "a reaction for one listed without any")
        XCTAssertEqual(AllergyCatalog.status(items[1], in: list), .new)
        AllergyCatalog.apply(items, to: &list)
        XCTAssertEqual(list.map(\.text), ["Penicillin (hives)", "Latex (anaphylaxis)"])
        XCTAssertEqual(AllergyCatalog.status(AllergyCatalog.parse("latex")[0], in: list), .recorded)
        XCTAssertEqual(AllergyCatalog.status(AllergyCatalog.parse("pcn mild")[0], in: list), .replaces("Penicillin (hives)"))
    }

    // MARK: The summary, and records saved before 1.9

    private func line(_ r: PatientRecord, _ label: String) -> PatientSummary.Line? { PatientSummary.historyLines(r).first { $0.label == label } }

    func testLegacyAllergiesShowAsTyped() {
        var r = PatientRecord()
        r.allergies = "penicillin (rash, hives); latex"
        XCTAssertEqual(PatientAllergyText.items(r).map(\.text), ["Penicillin (rash, hives)", "Latex"])
        XCTAssertTrue(PatientAllergyText.items(r).allSatisfy(\.legacy))
        XCTAssertEqual(line(r, "Allergies")?.text, "Penicillin (rash, hives); Latex", "as before 1.9")
        XCTAssertEqual(r.allergies, "penicillin (rash, hives); latex", "the saved text is not changed")
        r.allergies = "latex - anaphylaxis"
        XCTAssertEqual(PatientAllergyText.items(r).first?.anaphylaxis, true)
        r.allergies = ""
        r.nkda = true
        XCTAssertEqual(line(r, "Allergies")?.text, "No known drug allergies")
    }

    func testAllergyListOnTheSummary() {
        var r = PatientRecord()
        r.allergyList = [PatientAllergy(name: "Penicillin", severity: "mild"), PatientAllergy(name: "latex", severity: "anaphylaxis")]
        let l = line(r, "Allergies")
        XCTAssertEqual(l?.text, "Penicillin (mild); Latex (anaphylaxis)")
        XCTAssertEqual(l?.alert, true)
        XCTAssertEqual(l?.marks, ["Latex (anaphylaxis)"], "anaphylaxis in red")
        // Typed text the list does not hold still shows; text it holds does not.
        r.allergies = "penicillin"
        XCTAssertEqual(line(r, "Allergies")?.text, "Penicillin (mild); Latex (anaphylaxis)")
        r.allergies = "chlorhexidine"
        XCTAssertEqual(line(r, "Allergies")?.text, "Penicillin (mild); Latex (anaphylaxis); Chlorhexidine")
    }

    func testMedicationListOnTheSummary() {
        var r = PatientRecord()
        r.homeMeds = MedicationCatalog.parse("metoprolol 25 mg bid, Eliquis 5 bid")
        r.medFlags = MedicationCatalog.flags(for: r.homeMeds)
        XCTAssertEqual(line(r, "Medications")?.text, "Metoprolol 25 mg bid; Apixaban 5 bid")
        XCTAssertEqual(line(r, "Medication alerts")?.text, "Anticoagulant", "the medication alerts as before")
        r.medications = "metoprolol, apixaban"
        XCTAssertEqual(line(r, "Medications")?.text, "Metoprolol 25 mg bid; Apixaban 5 bid", "the typed list holds nothing more")
        r.medications = "metoprolol, gabapentin"
        XCTAssertEqual(line(r, "Medications")?.text, "Metoprolol 25 mg bid; Apixaban 5 bid; Metoprolol, Gabapentin")
        var old = PatientRecord()
        old.medications = "amlodipine, metoprolol"
        XCTAssertEqual(line(old, "Medications")?.text, "Amlodipine, Metoprolol", "a record saved before 1.9")
    }

    func testDemoPatient() {
        let r = PatientDemo.meds
        XCTAssertEqual(r.homeMeds.count, 7)
        XCTAssertTrue(r.medFlags.isSuperset(of: ["anticoagulant", "glp1", "insulin", "betablocker", "acei", "statin"]))
        XCTAssertEqual(r.allergyList.map(\.text), ["Penicillin (mild, rash)", "Sulfa drugs (hives)", "Latex (anaphylaxis)"])
    }

    // MARK: Saved items decode with keys missing

    func testDecodingWithMissingKeys() throws {
        let med = try JSONDecoder().decode(PatientMed.self, from: Data(#"{"name":"Metoprolol"}"#.utf8))
        XCTAssertEqual(med.name, "Metoprolol")
        XCTAssertEqual(med.dose, "")
        XCTAssertNil(med.catalogID)
        let empty = try JSONDecoder().decode(PatientMed.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.name, "")
        let a = try JSONDecoder().decode(PatientAllergy.self, from: Data(#"{"name":"Latex"}"#.utf8))
        XCTAssertEqual(a.name, "Latex")
        XCTAssertNil(a.severity)
        XCTAssertEqual(a.reaction, "")
        let b = try JSONDecoder().decode(PatientAllergy.self, from: Data(#"{"severity":"anaphylaxis","reaction":"hives"}"#.utf8))
        XCTAssertEqual(b.severity, "anaphylaxis")
        XCTAssertEqual(b.reaction, "hives")
        XCTAssertEqual(b.name, "")
        // A record saved before 1.9: no lists.
        var old = PatientRecord()
        old.allergies = "penicillin"
        old.medications = "metoprolol"
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any] ?? [:]
        json.removeValue(forKey: "allergyList")
        json.removeValue(forKey: "homeMeds")
        let opened = try JSONDecoder().decode(PatientRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(opened.allergyList.isEmpty)
        XCTAssertTrue(opened.homeMeds.isEmpty)
        XCTAssertEqual(opened.allergies, "penicillin")
        // Round trip.
        var r = PatientRecord()
        r.homeMeds = MedicationCatalog.parse("Eliquis 5 bid")
        r.allergyList = AllergyCatalog.parse("latex anaphylaxis")
        let back = try JSONDecoder().decode(PatientRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.homeMeds, r.homeMeds)
        XCTAssertEqual(back.allergyList, r.allergyList)
    }

    // MARK: Infusions (1.9: a larger list, split by spaces)

    private func drips(_ s: String, choices: [String: String] = [:]) -> [String] { InfusionEntry.read(s, choices: choices).items.map(\.label) }

    func testDripsSplitBySpaces() {
        XCTAssertEqual(drips("norepi 0.05 vaso 0.04"), ["Norepinephrine 0.05 mcg/kg/min", "Vasopressin 0.04 units/min"])
        XCTAssertEqual(drips("norepi 0.05 mcg/kg/min vaso 0.04"), ["Norepinephrine 0.05 mcg/kg/min", "Vasopressin 0.04 units/min"])
        XCTAssertEqual(drips("angiotensin 2 20 vaso 0.03"), ["Angiotensin II 20 ng/kg/min", "Vasopressin 0.03 units/min"], "the 2 of the name")
        XCTAssertEqual(drips("nitric oxide 20 milri 0.25"), ["Nitric oxide, inhaled 20 ppm", "Milrinone 0.25 mcg/kg/min"])
        XCTAssertEqual(drips("norepi vaso 0.04"), ["Norepinephrine", "Vasopressin 0.04 units/min"], "names side by side")
        // The last word being typed: the typeahead offers it, the drip before stays.
        XCTAssertEqual(drips("norepi 0.05 va"), ["Norepinephrine 0.05 mcg/kg/min"])
        XCTAssertEqual(InfusionEntry.suggestions("norepi 0.05 va").first?.id, "vasopressin")
        XCTAssertEqual(drips("norepi 0.05 mcg"), ["Norepinephrine 0.05 mcg"], "a unit being typed is not a drug")
    }

    func testTheLargerDripList() {
        let want: [String: String] = [
            "fent": "fentanyl", "midaz": "midazolam", "hydromorphone": "hydromorphone", "cisatracurium": "cisatracurium",
            "roc": "rocuronium", "vec": "vecuronium", "argatroban": "argatroban", "eptifibatide": "eptifibatide", "kcl": "potassium-chloride",
            "mag": "magnesium", "bicarb": "sodium-bicarbonate", "tpn": "tpn", "intralipid": "lipids", "octreotide": "octreotide",
            "protonix": "pantoprazole", "pitocin": "oxytocin", "pge1": "alprostadil", "labetalol": "labetalol", "treprostinil": "treprostinil",
            "iloprost": "iloprost", "procainamide": "procainamide", "methylene blue": "methylene-blue", "lasix": "furosemide",
            "cangrelor": "cangrelor", "tpa": "alteplase", "hypertonic saline": "hypertonic-saline", "pentobarbital": "pentobarbital",
        ]
        for (w, id) in want { XCTAssertEqual(InfusionEntry.matches(w).map(\.id), [id], w) }
        XCTAssertEqual(Set(InfusionEntry.matches("epoprostenol").map(\.id)), ["iepo", "epoprostenol-iv"], "inhaled or IV: asked")
        XCTAssertEqual(Set(InfusionEntry.matches("calcium").map(\.id)), ["calcium-chloride", "calcium-gluconate"])
        XCTAssertEqual(Set(InfusionEntry.drugs.map(\.id)).count, InfusionEntry.drugs.count, "ids are unique")
        // Units typed for the new drips.
        XCTAssertEqual(drips("fent 50 mcg/h"), ["Fentanyl 50 mcg/h"])
        XCTAssertEqual(drips("kcl 10 meq/h"), ["Potassium chloride 10 mEq/h"])
        XCTAssertEqual(drips("pit 2 mu/min"), ["Oxytocin 2 milliunits/min"])
        XCTAssertEqual(drips("mag 2 g/h"), ["Magnesium sulfate 2 g/h"])
        // No unit in the Reference table: asked.
        let vec = InfusionEntry.read("vec 1")
        XCTAssertTrue(vec.items.isEmpty)
        XCTAssertEqual(vec.questions.first?.options.map(\.id), ["mcg/kg/min", InfusionEntry.noUnit])
        XCTAssertEqual(drips("vec 1", choices: ["unit:vecuronium:1": "mcg/kg/min"]), ["Vecuronium 1 mcg/kg/min"])
        XCTAssertEqual(InfusionEntry.drugID(of: "Parenteral nutrition (TPN)"), "tpn")
        XCTAssertEqual(InfusionEntry.drugID(of: "Epoprostenol, IV"), "epoprostenol-iv")
    }
}

/// Reading speed with the medication and allergy lists: each keystroke of a typed line runs the type-ahead and the reader.
/// Named with a Z so it runs last, beside the procedure speed tests; each prints one "MEDICATION SPEED TEST" line.
final class ZMedicationSpeedTests: XCTestCase {
    private func seconds(_ body: () -> Void) -> Double {
        let t = CFAbsoluteTimeGetCurrent()
        body()
        return CFAbsoluteTimeGetCurrent() - t
    }

    private let medLines = ["metoprolol 25 mg bid lisinopril 10 atorvastatin 40", "Eliquis 5 bid, Mounjaro 7.5 weekly, Jardiance 10",
                            "insulin glargine 30 units qhs and humalog sliding scale", "Toprol XL 50, Entresto 49/51 bid, spironolactone 25",
                            "levothyroxine 100 mcg, omeprazole 20, sertraline 100, gabapentin 300 tid"]
    private let allergyLines = ["PCN - rash, sulfa (hives), latex anaphylaxis", "codeine nausea, morphine itching, chlorhexidine"]

    func testTypingStaysFast() {
        _ = MedicationCatalog.search("warm")
        _ = AllergyCatalog.search("warm")
        var calls = 0
        let t = seconds {
            for _ in 0..<3 {
                for l in medLines {
                    var s = ""
                    for ch in l {
                        s.append(ch)
                        _ = MedicationCatalog.typeahead(s)
                        _ = MedicationCatalog.reading(s)
                        calls += 1
                    }
                }
                for l in allergyLines {
                    var s = ""
                    for ch in l {
                        s.append(ch)
                        _ = AllergyCatalog.typeahead(s)
                        _ = AllergyCatalog.reading(s)
                        calls += 1
                    }
                }
            }
        }
        print("MEDICATION SPEED TEST: \(calls) keystrokes (type-ahead + reading) in \(String(format: "%.1f", t * 1000)) ms, "
              + "\(String(format: "%.3f", t * 1000 / Double(calls))) ms each, \(MedicationCatalog.entries.count) medications")
        XCTAssertLessThan(t / Double(calls), 0.02, "a keystroke in the medication or allergy field")
        let prefixes = ["m", "me", "met", "meto", "metop", "e", "el", "eli", "in", "ins", "ins g", "ins gla", "a", "as", "asp"]
        let n = 20
        let s = seconds { for _ in 0..<n { for p in prefixes { _ = MedicationCatalog.search(p, limit: 8) } } }
        print("MEDICATION SPEED TEST search: \(String(format: "%.3f", s * 1000 / Double(n * prefixes.count))) ms per query")
        XCTAssertLessThan(s / Double(n * prefixes.count), 0.01)
    }
}
