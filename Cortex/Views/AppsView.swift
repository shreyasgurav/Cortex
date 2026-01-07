
import SwiftUI
import AppKit

struct AppInfo: Identifiable, Hashable {
    let id: String // bundle identifier
    let name: String
    let icon: NSImage
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct AppsView: View {
    @ObservedObject var appState: AppState
    @State private var installedApps: [AppInfo] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Allowed Apps")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Cortex only works in enabled apps. Your choices are saved.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // App List
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Scanning applications...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(installedApps) { app in
                        AppRow(
                            name: app.name,
                            bundleId: app.id,
                            icon: app.icon,
                            isEnabled: Binding(
                                get: { appState.isAppEnabled(app.id) },
                                set: { enabled in appState.setAppEnabled(app.id, enabled: enabled) }
                            )
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            refreshInstalledApps()
        }
    }
    
    private func refreshInstalledApps() {
        isLoading = true
        
        Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let appDirs = ["/Applications", "/System/Applications"]
            var foundApps: [AppInfo] = []
            
            for dir in appDirs {
                let url = URL(fileURLWithPath: dir)
                if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isApplicationKey], options: .skipsHiddenFiles) {
                    for appUrl in contents where appUrl.pathExtension == "app" {
                        if let bundle = Bundle(url: appUrl),
                           let bundleId = bundle.bundleIdentifier {
                            
                            let name = (bundle.infoDictionary?["CFBundleName"] as? String) ?? 
                                      (bundle.infoDictionary?["CFBundleExecutable"] as? String) ?? 
                                      appUrl.deletingPathExtension().lastPathComponent
                            
                            let icon = NSWorkspace.shared.icon(forFile: appUrl.path)
                            foundApps.append(AppInfo(id: bundleId, name: name, icon: icon))
                        }
                    }
                }
            }
            
            // Deduplicate by bundleId
            var uniqueAppsDict: [String: AppInfo] = [:]
            for app in foundApps {
                uniqueAppsDict[app.id] = app
            }
            
            let sortedApps = Array(uniqueAppsDict.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            await MainActor.run {
                self.installedApps = sortedApps
                self.isLoading = false
            }
        }
    }
}

struct AppRow: View {
    let name: String
    let bundleId: String
    let icon: NSImage
    @Binding var isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(bundleId)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }
}
