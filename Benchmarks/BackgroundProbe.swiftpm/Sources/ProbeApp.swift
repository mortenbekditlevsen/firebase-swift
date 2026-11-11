// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI

@main
struct ProbeApp: App {
    @State private var model = ProbeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.sceneBecameActive()
            case .background: model.sceneEnteredBackground()
            default: break
            }
        }
    }
}

struct ContentView: View {
    @Bindable var model: ProbeModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Database") {
                    TextField("https://<project>-default-rtdb.firebaseio.com", text: $model.databaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Picker("Transport", selection: $model.transport) {
                        ForEach(ProbeTransport.allCases) { Text($0.title).tag($0) }
                    }
                    Button(model.isRunning ? "Stop" : "Start") {
                        model.isRunning ? model.stop() : model.start()
                    }
                }

                Section("Now") {
                    LabeledContent("Connected", value: model.isRunning ? (model.isConnected ? "Yes" : "No") : "–")
                    LabeledContent("Network", value: model.network)
                    Button("Test now") {
                        Task { await model.sendNonce() }
                    }
                    .disabled(!model.isRunning)
                }

                Section {
                    Picker("Scenario", selection: $model.scenario) {
                        ForEach(ProbeScenario.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text(model.scenario.instructions)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Note (optional)", text: $model.note)
                } header: {
                    Text("Scenario")
                } footer: {
                    Text("Each return to the foreground writes a value over REST and times how long until the connection delivers it. No delivery within \(Int(model.timeout.components.seconds)) s counts as a connection that never recovered.")
                }

                Section("Results") {
                    if model.summaries.isEmpty {
                        Text("No foreground tests yet.").foregroundStyle(.secondary)
                    }
                    ForEach(model.summaries) { summary in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(summary.scenario.rawValue) · \(summary.transport.rawValue)").font(.headline)
                            Text(Self.describe(summary)).font(.footnote).monospacedDigit()
                        }
                    }
                    ShareLink("Share the log", item: model.logURL)
                    Button("Clear the log", role: .destructive) { model.clearLog() }
                }

                Section("Events") {
                    ForEach(model.events.suffix(50).reversed()) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(event.kind.rawValue)\(event.sinceForeground.map { String(format: " after %.0f ms", $0) } ?? "")")
                                .font(.subheadline)
                            Text("\(event.date.formatted(date: .omitted, time: .standard)) · \(event.transport.rawValue) · \(event.network)\(event.detail.map { " · \($0)" } ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Background probe")
        }
        .task {
            // For a run without tapping (e.g. in the Simulator):
            // -autostart, with -databaseURL <url> and -transport <name>.
            guard ProcessInfo.processInfo.arguments.contains("-autostart") else { return }
            model.start()
            try? await Task.sleep(for: .seconds(3))
            await model.sendNonce()
        }
    }

    private static func describe(_ summary: ProbeModel.Summary) -> String {
        var parts = ["\(summary.tests) tests"]
        if let median = summary.medianMilliseconds {
            parts.append(String(format: "median %.0f ms", median))
        }
        if let worst = summary.worstMilliseconds {
            parts.append(String(format: "worst %.0f ms", worst))
        }
        parts.append("\(summary.timeouts) never recovered")
        parts.append("\(summary.spuriousDisconnects) spurious disconnects")
        return parts.joined(separator: " · ")
    }
}
