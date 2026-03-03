//
//  FeedbackView.swift
//  SipBuddy


import SwiftUI
import MessageUI

struct FeedbackView: View {
    @EnvironmentObject var app: AppState

    // MARK: - All-cases answers
    @State private var yourName = ""
    @State private var product: Product? = nil
    @State private var whereUsed = ""
    @State private var concernBefore = 3
    @State private var confidenceAfter = 3
    @State private var workingConfidence = 3
    @State private var interfered = 3
    @State private var forgotUsing = 3
    @State private var easyUse = 3
    @State private var easyAfterDrinks = 3
    @State private var setupAmount = 3
    @State private var appearancePublic = 3
    @State private var noticeableToOthers = 3
    @State private var conversationShort = ""
    @State private var comfortExplain = 3

    // MARK: - Sip Buddy
    @State private var alertSpeed = 3
    @State private var connectionIssues = 3
    @State private var alertsClear = 3
    @State private var footageHelpful = 3
    @State private var detectionEffective = 3
    @State private var falsePositives = 3
    @State private var ledBrightness = 3
    @State private var ledUrgency = 3
    @State private var batteryLife = 3
    @State private var batteryHours: String = ""
    @State private var deviceConsistency = 3
    @State private var fitAllDrinks = 3
    @State private var deviceSize = 3
    @State private var appLiked = 3
    @State private var appChange = ""

    // MARK: - Looks-Like Cases
    private let caseOptions = ["— Select —","Case A","Case B","Case C"]
    @State private var caseBestIdx = 0
    @State private var casesDiscreet = 3
    @State private var caseUsePublicIdx = 0
    @State private var caseChange = ""

    // MARK: - Night Cap
    @State private var comfortWear = 3
    @State private var comfortableAfterUse = 3

    // MARK: - Test Strips
    @State private var wetConcern = 3
    @State private var readResults = 3
    @State private var stripsAccurate = 3
    @State private var stripsDiscreet = 3

    // MARK: - End questions
    private let bestSituations = ["Bars","House parties","Festivals","Clubs","Other"]
    @State private var bestSituationsIdx = 0
    @State private var preventRegularUse = ""
    @State private var changeOneThing = ""
    @State private var questionsBeforeUse = ""
    @State private var worthBuying = ""
    @State private var likelyToBuy = 3
    @State private var willingToPay: Double = 50
    @State private var quotes = ""
    @State private var otherComments = ""

    // MARK: - Mail / Share
    @State private var mailItem: MailItem? = nil
    @State private var shareItem: ShareItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider()
            Form {
                // 1) All cases
                Section(header: Text("All Cases Survey")) {
                    TextField("Your Name", text: $yourName)

                    Picker("What product are you using?",
                           selection: Binding(get: { product ?? .none },
                                              set: { product = $0 == .none ? nil : $0 })) {
                        ForEach(Product.allCases, id: \.self) { p in
                            Text(p.title).tag(p)
                        }
                    }

                    // CHANGED: TextField -> TextEditorLabeled
                    TextEditorLabeled("Where did you use this product at? (Bar, Club, House party, Festival, etc)",
                                      text: $whereUsed)

                    FivePointQuestion("Before using this product, how concerned were you about drink tampering?",
                                      labels: ("not concerned at all","somewhat concerned","very concerned"),
                                      value: $concernBefore)

                    FivePointQuestion("After using this product, how confident do you feel in avoiding drink tampering?",
                                      labels: ("not confident","neutral","very confident"),
                                      value: $confidenceAfter)

                    FivePointQuestion("How confident were you that the product was working during use?",
                                      labels: ("not confident","neutral","very confident"),
                                      value: $workingConfidence)

                    FivePointQuestion("Did the product interfere with your normal drinking experience",
                                      labels: ("never","occasionally","very often"),
                                      value: $interfered)

                    FivePointQuestion("How often did you forget that you were using it?",
                                      labels: ("never","occasionally","very often"),
                                      value: $forgotUsing)

                    FivePointQuestion("How easy was the device to use?",
                                      labels: ("very difficult","neutral","very easy"),
                                      value: $easyUse)

                    FivePointQuestion("After having a few drinks, how easy was this device to use?",
                                      labels: ("very difficult","neutral","very easy"),
                                      value: $easyAfterDrinks)

                    FivePointQuestion("How much setup was required?",
                                      labels: ("almost none","normal amount","way too much"),
                                      value: $setupAmount)

                    FivePointQuestion("How would you rate the appearance of the product in public settings?",
                                      labels: ("very ugly","neutral","very good looking"),
                                      value: $appearancePublic)

                    FivePointQuestion("How noticeable do you feel the product was to others?",
                                      labels: ("very obvious","neutral","very discreet"),
                                      value: $noticeableToOthers)

                    // CHANGED: TextField -> TextEditorLabeled
                    TextEditorLabeled("Did the product start a conversation? If so, what was the tone? (supportive, skeptical, curious, etc)",
                                      text: $conversationShort)

                    FivePointQuestion("How comfortable would you feel explaining this product to others if asked about it?",
                                      labels: ("not at all","neutral","very comfortable"),
                                      value: $comfortExplain)
                }

                // 2) Branching by product
                if let prod = product {
                    Section(header: Text(prod.sectionTitle)) {
                        switch prod {
                        case .sipBuddy:
                            FivePointQuestion("How quickly did the alert reach your phone after tampering was detected?",
                                              labels: ("very slowly","normal","very fast"),
                                              value: $alertSpeed)

                            FivePointQuestion("Did you have any connection issues between the device and app?",
                                              labels: ("never","occasionally","very often"),
                                              value: $connectionIssues)

                            FivePointQuestion("Did you feel that the alert notifications were clear and actionable?",
                                              labels: ("not at all","somewhat","extremely clear"),
                                              value: $alertsClear)

                            FivePointQuestion("How helpful was the video footage in understanding what happened to your drink?",
                                              labels: ("not helpful","okay","very helpful"),
                                              value: $footageHelpful)

                            FivePointQuestion("How effective was it in detecting drink spiking?",
                                              labels: ("terrible","decent","fantastic"),
                                              value: $detectionEffective)

                            FivePointQuestion("Did the device produce any false positives?",
                                              labels: ("never","occasionally","very often"),
                                              value: $falsePositives)

                            FivePointQuestion("How was the brightness of the LED?",
                                              labels: ("too dim","perfect","too bright"),
                                              value: $ledBrightness)

                            FivePointQuestion("Did the flashes from the LED communicate the urgency?",
                                              labels: ("not at all","somewhat","very well"),
                                              value: $ledUrgency)

                            FivePointQuestion("How would you rate the battery life?",
                                              labels: ("terrible","decent","fantastic"),
                                              value: $batteryLife)

                            HStack {
                                Text("How long did the battery last? (hours)")
                                Spacer()
                                TextField("e.g. 8", text: $batteryHours)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 100)
                            }

                            FivePointQuestion("How consistent do you feel the device is?",
                                              labels: ("very inconsistent","decent","perfectly consistent"),
                                              value: $deviceConsistency)

                            FivePointQuestion("How well did it fit on all of your drinks",
                                              labels: ("didn’t fit any of them","fit quite a few","fit every single one"),
                                              value: $fitAllDrinks)

                            FivePointQuestion("What did you think of the size of the device?",
                                              labels: ("way too small","perfect","way too big"),
                                              value: $deviceSize)

                            FivePointQuestion("How well did you like the app?",
                                              labels: ("terrible","decent","fantastic"),
                                              value: $appLiked)

                            // CHANGED: TextField -> TextEditorLabeled
                            TextEditorLabeled("What would you change about it?", text: $appChange)
                        case .looksLike:
                            Picker("Which style of case did you like best?", selection: $caseBestIdx) {
                                ForEach(0..<caseOptions.count, id: \.self) { i in
                                    Text(caseOptions[i]).tag(i)
                                }
                            }
                            FivePointQuestion("Did the cases make the device more discreet?",
                                              labels: ("not at all","somewhat","absolutely"),
                                              value: $casesDiscreet)
                            Picker("Which case would you actually use in public?", selection: $caseUsePublicIdx) {
                                ForEach(0..<caseOptions.count, id: \.self) { i in
                                    Text(caseOptions[i]).tag(i)
                                }
                            }
                            // CHANGED: TextField -> TextEditorLabeled
                            TextEditorLabeled("If you could change one thing about them, what would it be?",
                                              text: $caseChange)
                        case .nightCap:
                            FivePointQuestion("How comfortable was the device on your wrist/in your hair?",
                                              labels: ("very uncomfortable","okay","very comfortable"),
                                              value: $comfortWear)
                            FivePointQuestion("Did you feel comfortable wearing the device after using it on a drink?",
                                              labels: ("not at all","somewhat","absolutely"),
                                              value: $comfortableAfterUse)
                        case .testStrips:
                            FivePointQuestion("Were you concerned about getting them wet at all?",
                                              labels: ("not at all","somewhat","absolutely"),
                                              value: $wetConcern)
                            FivePointQuestion("Did you understand how to read the results easily?",
                                              labels: ("not at all","somewhat","absolutely"),
                                              value: $readResults)
                            FivePointQuestion("Do you feel like they were accurate?",
                                              labels: ("not at all","somewhat","absolutely"),
                                              value: $stripsAccurate)
                            FivePointQuestion("How discreet was using the product?",
                                              labels: ("very obvious","neutral","very discreet"),
                                              value: $stripsDiscreet)
                        case .none:
                            EmptyView()
                        }
                    }
                } else {
                    Section {
                        Text("Pick a product above to continue…")
                            .foregroundColor(.secondary)
                    }
                }

                // 3) End questions
                Section(header: Text("End Questions")) {
                    Picker("What situations do you think this product is best suited for?",
                           selection: $bestSituationsIdx) {
                        ForEach(0..<bestSituations.count, id:\.self) { i in
                            Text(bestSituations[i]).tag(i)
                        }
                    }

                    // CHANGED: TextField -> TextEditorLabeled
                    TextEditorLabeled("What would prevent you from using this product regularly", text: $preventRegularUse)

                    // CHANGED: TextField -> TextEditorLabeled
                    TextEditorLabeled("If you could change one thing about this app or product what would it be?",
                                      text: $changeOneThing)

                    // (already multiline)
                    TextEditorLabeled("Do you have any questions that should have been addressed before you used the device?",
                                      text: $questionsBeforeUse)
                    TextEditorLabeled("What would make this product worth buying for you?",
                                      text: $worthBuying)

                    FivePointQuestion("How likely would you be to buy this product?",
                                      labels: ("not likely","neutral","very likely"),
                                      value: $likelyToBuy)

                    VStack(alignment: .leading) {
                        Text("How much would you pay for the device?  $\(Int(willingToPay))")
                        Slider(value: $willingToPay, in: 0...300, step: 1)
                    }

                    // CHANGED: TextField -> TextEditorLabeled
                    TextEditorLabeled("Are there any quotes or testimonials that you would like to submit here?",
                                      text: $quotes)
                    // CHANGED: TextField -> TextEditorLabeled
                    TextEditorLabeled("Other comments?", text: $otherComments)
                }

                // Send
                Section {
                    Button {
                        let url = exportCSV()
                        if MFMailComposeViewController.canSendMail() {
                            mailItem = MailItem(url: url)
                        } else {
                            shareItem = ShareItem(url: url)
                        }
                    } label: {
                        Label("Send Survey via Email (.csv)", systemImage: "paperplane.fill")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)   // swipe down to dismiss (iOS 16+)
        .toolbar {                                  // a Done button above the keyboard
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        // Mail sheet (item-based to avoid blank first presentation)
        .sheet(item: $mailItem) { item in
            MailView(recipient: "jossrossman17@gmail.com",
                     subject: "SipBuddy Survey Response",
                     body: "Attached is the CSV export of a survey response.",
                     attachmentURL: item.url,
                     attachmentMime: "text/csv",
                     attachmentName: item.url.lastPathComponent) {
                mailItem = nil
            }
        }
        // Share sheet fallback
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        
    } // END Form

    
    // MARK: - Helper to dismiss keyboard
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
    
    

    // MARK: - CSV
    private func exportCSV() -> URL {
        var rows: [(String,String)] = []

        func add(_ q: String, _ a: String) { rows.append((q, a)) }
        func s(_ n: Int) -> String { String(n) }

        // All cases
        add("Your Name", yourName)
        add("What product are you using?", product?.title ?? "")
        add("Where used", whereUsed)
        add("Concern before using (1-5)", s(concernBefore))
        add("Confidence avoiding tampering after using (1-5)", s(confidenceAfter))
        add("Confidence it was working (1-5)", s(workingConfidence))
        add("Interfered with normal experience (1-5)", s(interfered))
        add("Forgot using it (1-5)", s(forgotUsing))
        add("Ease of use (1-5)", s(easyUse))
        add("Ease after drinks (1-5)", s(easyAfterDrinks))
        add("Setup required (1-5)", s(setupAmount))
        add("Appearance in public (1-5)", s(appearancePublic))
        add("Noticeable to others (1-5)", s(noticeableToOthers))
        add("Conversation (short)", conversationShort)
        add("Comfort explaining (1-5)", s(comfortExplain))

        // Branch
        switch product {
        case .sipBuddy?:
            add("Alert speed (1-5)", s(alertSpeed))
            add("Connection issues (1-5)", s(connectionIssues))
            add("Alerts clear (1-5)", s(alertsClear))
            add("Footage helpful (1-5)", s(footageHelpful))
            add("Detection effective (1-5)", s(detectionEffective))
            add("False positives (1-5)", s(falsePositives))
            add("LED brightness (1-5)", s(ledBrightness))
            add("LED conveyed urgency (1-5)", s(ledUrgency))
            add("Battery life (1-5)", s(batteryLife))
            add("Battery lasted (hours)", batteryHours)
            add("Consistency (1-5)", s(deviceConsistency))
            add("Fit all drinks (1-5)", s(fitAllDrinks))
            add("Device size (1-5)", s(deviceSize))
            add("App liked (1-5)", s(appLiked))
            add("App change (short)", appChange)
        case .looksLike?:
            add("Case liked best", caseOptions[safe: caseBestIdx] ?? "")
            add("Cases made device more discreet (1-5)", s(casesDiscreet))
            add("Case would use in public", caseOptions[safe: caseUsePublicIdx] ?? "")
            add("Change about cases (short)", caseChange)
        case .nightCap?:
            add("Comfort to wear (1-5)", s(comfortWear))
            add("Comfortable wearing after use (1-5)", s(comfortableAfterUse))
        case .testStrips?:
            add("Concern about getting wet (1-5)", s(wetConcern))
            add("Understood reading results (1-5)", s(readResults))
            add("Felt accurate (1-5)", s(stripsAccurate))
            add("Discreet to use (1-5)", s(stripsDiscreet))
        default: break
        }

        // End
        add("Best situations (dropdown)", bestSituations[safe: bestSituationsIdx] ?? "")
        add("Prevent regular use (short)", preventRegularUse)
        add("Change one thing (short)", changeOneThing)
        add("Questions before use (long)", questionsBeforeUse)
        add("Worth buying because (long)", worthBuying)
        add("Likely to buy (1-5)", s(likelyToBuy))
        add("Willing to pay ($)", String(Int(willingToPay)))
        add("Quotes/testimonials (short)", quotes)
        add("Other comments (short)", otherComments)

        // Build CSV
        let header = "Question,Answer\n"
        let body = rows.map { "\"\($0.0.replacingOccurrences(of: "\"", with: "\"\""))\",\" \($0.1.replacingOccurrences(of: "\"", with: "\"\""))\""}.joined(separator: "\n")
        let csv = header + body

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SipBuddy_Survey_\(Date().isoStamp).csv")
        try? csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Supporting types & views

private enum Product: String, CaseIterable {
    case none = "— Select —"
    case sipBuddy = "Sip Buddy"
    case looksLike = "Looks Like Sip Buddy"
    case nightCap = "Night Cap"
    case testStrips = "Test Strips"

    var title: String { rawValue }
    var sectionTitle: String {
        switch self {
        case .sipBuddy:   return "Sip Buddy Questions"
        case .looksLike:  return "Looks-Like Cases Questions"
        case .nightCap:   return "Night Cap Questions"
        case .testStrips: return "Test Strip Questions"
        case .none:       return ""
        }
    }
}

private struct FivePointQuestion: View {
    let title: String
    let labels: (String,String,String) // above 1,3,5
    @Binding var value: Int

    init(_ title: String, labels: (String,String,String), value: Binding<Int>) {
        self.title = title
        self.labels = labels
        self._value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            HStack {
                Text(labels.0).font(.caption2).frame(maxWidth: .infinity, alignment: .leading)
                Text(labels.1).font(.caption2).frame(maxWidth: .infinity, alignment: .center)
                Text(labels.2).font(.caption2).frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                       in: 1...5, step: 1)
                Text("\(value)")
                    .font(.caption).monospacedDigit()
                    .frame(width: 26, alignment: .trailing)
            }
        }
    }
}

private struct TextEditorLabeled: View {
    let title: String
    @Binding var text: String
    init(_ title: String, text: Binding<String>) {
        self.title = title; self._text = text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            TextEditor(text: $text).frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
        }
    }
}

private struct MailView: UIViewControllerRepresentable {
    var recipient: String
    var subject: String
    var body: String
    var attachmentURL: URL
    var attachmentMime: String
    var attachmentName: String
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: attachmentURL) {
            vc.addAttachmentData(data, mimeType: attachmentMime, fileName: attachmentName)
        }
        return vc
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true) { self.onFinish() }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// Identifiable wrappers so .sheet(item:) never builds a blank sheet
private struct MailItem: Identifiable { let id = UUID(); let url: URL }
private struct ShareItem: Identifiable { let id = UUID(); let url: URL }
//    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Date {
    var isoStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: self)
    }
}
