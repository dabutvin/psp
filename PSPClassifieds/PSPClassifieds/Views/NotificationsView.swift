import SwiftUI

/// View for managing notification subscriptions and settings.
struct NotificationsView: View {
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var newSubscriptionText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            List {
                masterSwitchSection
                
                if notificationManager.notificationsEnabled {
                    allPostsSection
                    
                    if !notificationManager.notifyAll {
                        searchSubscriptionsSection
                    }
                }
                
                if notificationManager.authorizationStatus == .denied {
                    permissionDeniedSection
                }
            }
            .navigationTitle("Notifications")
            .refreshable {
                await notificationManager.fetchFromServer()
            }
            .task {
                await notificationManager.checkAuthorizationStatus()
                await notificationManager.fetchFromServer()
            }
        }
    }
    
    // MARK: - Sections
    
    private var masterSwitchSection: some View {
        Section {
            Toggle("Notifications", isOn: Binding(
                get: { notificationManager.notificationsEnabled },
                set: { newValue in
                    Task { await notificationManager.setNotificationsEnabled(newValue) }
                }
            ))
            .accessibilityLabel("Master notifications toggle")
            .accessibilityHint("Turn off to stop all notifications from PSP Classifieds")
        } footer: {
            Text("Turn off to stop all notifications from PSP Classifieds")
        }
    }
    
    private var allPostsSection: some View {
        Section {
            Toggle("All Posts", isOn: Binding(
                get: { notificationManager.notifyAll },
                set: { newValue in
                    Task { await notificationManager.setNotifyAll(newValue) }
                }
            ))
            .accessibilityLabel("Notify for all posts toggle")
            .accessibilityHint("When enabled, you'll receive a notification for every new post")
        } footer: {
            Text("Get notified for every new post")
        }
    }
    
    private var searchSubscriptionsSection: some View {
        Section {
            addSubscriptionRow
            
            if notificationManager.searchFilters.isEmpty {
                emptySubscriptionsView
            } else {
                subscriptionsList
            }
        } header: {
            Text("Search Subscriptions")
        } footer: {
            if notificationManager.searchFilters.isEmpty {
                Text("Enter a search term above to get notified when new matching posts appear")
            } else {
                Text("Swipe left to remove a subscription")
            }
        }
    }
    
    private var addSubscriptionRow: some View {
        HStack {
            TextField("Add search term...", text: $newSubscriptionText)
                .focused($isTextFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    addSubscription()
                }
                .accessibilityLabel("New subscription search term")
                .accessibilityHint("Enter a search term to subscribe to")
            
            Button {
                addSubscription()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(newSubscriptionText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.blue)
            }
            .disabled(newSubscriptionText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Add subscription")
            .accessibilityHint(newSubscriptionText.isEmpty ? "Enter a search term first" : "Subscribe to \(newSubscriptionText)")
        }
    }
    
    private func addSubscription() {
        let term = newSubscriptionText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        
        Task {
            await notificationManager.subscribeToSearchTerm(term)
            newSubscriptionText = ""
            isTextFieldFocused = false
        }
    }
    
    private var emptySubscriptionsView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "bell.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("No search subscriptions")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No search subscriptions")
            Spacer()
        }
        .listRowBackground(Color.clear)
    }
    
    private var subscriptionsList: some View {
        ForEach(notificationManager.searchFilters, id: \.self) { term in
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(term)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Subscribed to \(term)")
            .accessibilityHint("Swipe left to unsubscribe")
        }
        .onDelete { indexSet in
            Task {
                for index in indexSet {
                    let term = notificationManager.searchFilters[index]
                    await notificationManager.unsubscribeFromSearchTerm(term)
                }
            }
        }
    }
    
    private var permissionDeniedSection: some View {
        Section {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Notifications are disabled in Settings")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: Notifications are disabled in device settings")
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .accessibilityHint("Opens the Settings app to enable notifications")
        } footer: {
            Text("Enable notifications in Settings to receive alerts for new posts")
        }
    }
}

#Preview {
    NotificationsView()
}
