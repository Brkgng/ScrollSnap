import SwiftUI

struct PermissionRequestView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Screen Recording Permission Required")
                .font(.title2)
                .bold()
            
            Text("ScrollSnap needs screen recording permission to capture screenshots.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            
            Text("Please enable it in System Preferences > Security & Privacy > Screen Recording, then relaunch the app.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(width: 450)
        .padding(40)
    }
}
