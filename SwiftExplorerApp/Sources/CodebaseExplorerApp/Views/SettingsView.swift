import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            supportSettings
                .tabItem {
                    Label("Help", systemImage: "questionmark.circle")
                }
        }
        .frame(width: 560, height: 390)
        .padding(20)
    }

    private var generalSettings: some View {
        Form {
            Section("Output") {
                Picker("Default format", selection: outputMarkdown) {
                    Text("Markdown").tag(true)
                    Text("Plain Text").tag(false)
                }
                .pickerStyle(.segmented)

                Toggle("Show filters in main window", isOn: showFilters)
            }

            Section("Scan defaults") {
                Toggle("Skip hidden files", isOn: skipHidden)

                HStack {
                    Slider(value: maxFileSizeKB, in: 32 ... 8192, step: 32) {
                        Text("Max file size")
                    }
                    .accessibilityValue("\(Int(preferences.values.maxFileSizeKB)) kilobytes")
                    .accessibilityHint("Files larger than this value are skipped")
                    Text("\(Int(preferences.values.maxFileSizeKB)) KB")
                        .font(.body.monospacedDigit())
                        .frame(width: 90, alignment: .trailing)
                }
            }

            Section("Extensions") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Include")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("swift,js,ts,tsx,jsx,md,txt,py", text: allowListString)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Included extensions")
                        .accessibilityHint("Enter extensions separated by commas or spaces")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Exclude")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("png,jpg,jpeg,gif,mp4,zip,bin,lock", text: excludeListString)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Excluded extensions")
                        .accessibilityHint("Enter extensions separated by commas or spaces")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var allowListString: Binding<String> {
        Binding(
            get: { preferences.values.allowList },
            set: { preferences.values.allowList = $0 }
        )
    }

    private var excludeListString: Binding<String> {
        Binding(
            get: { preferences.values.excludeList },
            set: { preferences.values.excludeList = $0 }
        )
    }

    private var maxFileSizeKB: Binding<Double> {
        Binding(
            get: { preferences.values.maxFileSizeKB },
            set: { preferences.values.maxFileSizeKB = $0 }
        )
    }

    private var skipHidden: Binding<Bool> {
        Binding(
            get: { preferences.values.skipHidden },
            set: { preferences.values.skipHidden = $0 }
        )
    }

    private var outputMarkdown: Binding<Bool> {
        Binding(
            get: { preferences.values.outputMarkdown },
            set: { preferences.values.outputMarkdown = $0 }
        )
    }

    private var showFilters: Binding<Bool> {
        Binding(
            get: { preferences.values.showFilters },
            set: { preferences.values.showFilters = $0 }
        )
    }

    private var supportSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Help & Privacy")
                        .font(.title3.weight(.semibold))
                    Text("Get support or review how the app handles local files and recovered output.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    AppLinks.openSupportPage()
                } label: {
                    Label("Open Support", systemImage: "lifepreserver")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    AppLinks.openPrivacyPolicy()
                } label: {
                    Label("Read Privacy Policy", systemImage: "hand.raised")
                }
                .buttonStyle(.bordered)
            }

            Text("Codebase Combiner works locally. It does not send source files, prompts, or usage data to the developer.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(4)
    }
}
