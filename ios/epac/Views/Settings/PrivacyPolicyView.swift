import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Last updated: April 27, 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("epac is a Canadian civic engagement app built by Riddim Software. This policy explains what data epac collects, how it is used, and your rights as a user.")
                    .font(.body)

                PolicySection(title: "No Account Required") {
                    Text("epac does not require you to create an account, provide an email address, or log in. You can use the full app without identifying yourself in any way.")
                }

                PolicySection(title: "Data We Do Not Collect") {
                    Text("epac does not collect, store, or transmit:")
                    BulletList(items: [
                        "Your name, email address, or any personal information",
                        "Your location or postal code (the postal code you enter to find your MP stays on your device only)",
                        "Your browsing or reading history within the app",
                        "Any analytics, crash reports, or usage telemetry sent to Riddim Software"
                    ])
                }

                PolicySection(title: "Data Stored on Your Device") {
                    Text("epac stores the following data locally on your device using Apple's SwiftData framework:")
                    BulletList(items: [
                        "Parliamentary data downloaded from official sources (Hansard debates, voting records, MP profiles, expenditures)",
                        "Your preferences: followed MPs, followed bills, followed topics, your saved postal code"
                    ])
                    Text("This data never leaves your device to Riddim Software's servers. It is not backed up to iCloud unless you have iCloud backup enabled for all apps.")
                }

                PolicySection(title: "Network Requests") {
                    Text("epac makes network requests to official Canadian government sources to download parliamentary data:")
                    BulletList(items: [
                        "Parliament of Canada (ourcommons.ca, api.openparliament.ca) — Hansard, voting records, MP profiles, bills, expenditures",
                        "Elections Canada (elections.ca) — Electoral data",
                        "Commissioner of Lobbying (lobbycanada.gc.ca) — Lobbying registry",
                        "Statistics Canada (statcan.gc.ca) — Census data references",
                        "represent.opennorth.ca — Postal code to riding lookup (used only in the App Clip)"
                    ])
                    Text("These requests are made directly from your device to the government's servers. Riddim Software does not operate a proxy or intermediary server.")
                }

                PolicySection(title: "Apple Platform Services") {
                    Text("epac uses standard iOS frameworks. Apple may collect data according to its own privacy policy when you use iOS features such as Siri or Spotlight search integration.")
                }

                PolicySection(title: "No Third-Party Advertising or Analytics") {
                    Text("epac contains no advertising SDKs, no analytics SDKs (such as Firebase, Amplitude, or Mixpanel), and no third-party tracking of any kind.")
                }

                PolicySection(title: "Newsletter") {
                    Text("If you sign up for Parliament Monthly on the website, your email address is used only to send that monthly digest and related confirmation or unsubscribe messages. Newsletter subscriptions are separate from the epac app, and you can unsubscribe at any time from the link in each email.")
                }

                PolicySection(title: "Children") {
                    Text("epac is not directed at children under 13. We do not knowingly collect information from children.")
                }

                PolicySection(title: "Changes to This Policy") {
                    Text("If this policy changes materially, we will update the date above and post the updated policy at epac.riddimsoftware.com/privacy.html.")
                }

                PolicySection(title: "Contact") {
                    Text("Questions about this policy? Contact us at epac@riddimsoftware.com.")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
    }
}

// MARK: - Supporting Views

private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\u{2022}")
                        .accessibilityHidden(true)
                    Text(item)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
