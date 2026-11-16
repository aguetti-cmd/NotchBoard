import SwiftUI
import EventKit
import NotchBoardCore

struct SettingsView: View {
    let model: AppModel

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Weather") {
                LabeledContent("Location", value: model.preferences.place.name)
                HStack {
                    TextField("Search a city", text: $query)
                        .onSubmit(search)
                    Button("Search", action: search).disabled(searching)
                }
                ForEach(results, id: \.self.latitude) { place in
                    Button {
                        model.weather.setPlace(place)
                        results = []
                        query = ""
                    } label: {
                        Text([place.name, place.country].compactMap { $0 }.joined(separator: ", "))
                    }
                }
            }

            Section("Claude usage") {
                Toggle("Show Claude usage card", isOn: Binding(
                    get: { model.preferences.showUsage },
                    set: { on in
                        model.preferences.showUsage = on
                        if on { model.usage.start() } else { model.usage.stop() }
                    }
                ))
                Text("Read locally from ~/.claude/projects. Shows this Mac only. Nothing is sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                permissionRow("Calendars", granted: model.agenda.eventAccess == .granted, anchor: "Privacy_Calendars")
                permissionRow("Reminders", granted: model.agenda.reminderAccess == .granted, anchor: "Privacy_Reminders")
                permissionRow("Control Music", granted: model.music.status != .notAuthorized, anchor: "Privacy_Automation")
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        loginError = model.preferences.setLaunchAtLogin(on)
                        launchAtLogin = model.preferences.launchAtLogin
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = model.preferences.launchAtLogin }
    }

    private func permissionRow(_ title: String, granted: Bool, anchor: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            Button("Open") { SystemSettings.open(anchor) }
        }
    }

    private func search() {
        searching = true
        Task {
            results = await model.weather.search(query)
            searching = false
        }
    }
}
