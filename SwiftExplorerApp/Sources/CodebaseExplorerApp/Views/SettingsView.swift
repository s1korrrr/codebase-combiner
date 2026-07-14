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
                    Label("Support", systemImage: "heart")
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
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Exclude")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("png,jpg,jpeg,gif,mp4,zip,bin,lock", text: excludeListString)
                        .textFieldStyle(.roundedBorder)
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
                Image(systemName: "heart.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.pink)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Support Codebase Combiner")
                        .font(.title3.weight(.semibold))
                    Text("If this tool saves you time, you can sponsor continued work.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Support link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(AppLinks.supportURL.absoluteString)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            HStack {
                Button {
                    AppLinks.openSupportPage()
                } label: {
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AppLinks.supportURL.absoluteString, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Spacer()
        }
        .padding(4)
    }
}
