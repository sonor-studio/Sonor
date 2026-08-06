import SwiftUI
import Hub

struct LanguageListView: View {
    let languages: [String]
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isSearchFocused: Bool
    
    var filteredLanguages: [String] {
        if searchText.isEmpty {
            return languages
        }
        return languages.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(t("Supported Languages"))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding()
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(t("Search language..."), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
            }
            .padding(10)
            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            Divider()
            
            // List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredLanguages, id: \.self) { language in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(language)
                                .font(.system(size: 14))
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            Divider().padding(.leading, 16)
                        }
                    }
                    if filteredLanguages.isEmpty {
                        Text(t("No languages found."))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            isSearchFocused = true
        }
    }
}
