import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)
            
            VStack(spacing: 4) {
                Text("Judge Chronos")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.Colors.primary)
                
                Text("Version 1.0.0 (Alpha)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Text("A mindful journaling & self-reflection app.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Divider()
            
            Text("Designed by Antigravity")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(width: 300, height: 300)
        .background(AppTheme.Colors.background)
    }
}
