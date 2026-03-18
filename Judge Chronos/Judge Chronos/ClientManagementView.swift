import SwiftUI

struct ClientManagementView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showingAddSheet = false
    @State private var editingClient: Client?
    @State private var selectedClientId: UUID?

    private var filteredClients: [Client] {
        let base = showArchived ? dataStore.clients : dataStore.clients.filter { !$0.archived }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.company?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search clients...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Toggle("Show Archived", isOn: $showArchived)
                    .toggleStyle(.checkbox)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            HSplitView {
                // Client List
                List(filteredClients, selection: $selectedClientId) { client in
                    ClientRowView(client: client)
                        .tag(client.id)
                        .contextMenu {
                            Button("Edit") { editingClient = client }
                            Divider()
                            Button("Delete") { dataStore.deleteClient(client) }
                        }
                }
                .listStyle(.plain)
                .frame(minWidth: 250)

                // Detail Panel
                if let selectedId = selectedClientId,
                   let client = dataStore.clients.first(where: { $0.id == selectedId }) {
                    ClientDetailView(client: client)
                } else {
                    VStack {
                        Image(systemName: "person.2")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Select a client")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Bottom Toolbar
            HStack {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Client", systemImage: "plus")
                }
                Spacer()
                Text("\(filteredClients.count) clients")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingAddSheet) {
            ClientEditorView(client: nil) { newClient in
                dataStore.addClient(newClient)
                showingAddSheet = false
            }
        }
        .sheet(item: $editingClient) { client in
            ClientEditorView(client: client) { updated in
                dataStore.updateClient(updated)
                editingClient = nil
            }
        }
    }
}

// MARK: - Client Row
struct ClientRowView: View {
    let client: Client

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(client.name)
                    .fontWeight(.medium)
                if client.archived {
                    Text("(Archived)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if let company = client.company, !company.isEmpty {
                Text(company)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Client Detail
struct ClientDetailView: View {
    let client: Client
    @EnvironmentObject private var dataStore: LocalDataStore

    private var clientProjects: [Project] {
        dataStore.projects.filter { $0.clientId == client.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(client.name)
                            .font(.title2)
                        if let company = client.company {
                            Text(company)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(client.currency)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(6)
                }

                Divider()

                // Contact Info
                if client.email != nil || client.phone != nil || client.address != nil {
                    GroupBox("Contact") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let email = client.email {
                                Label(email, systemImage: "envelope")
                                    .font(.caption)
                            }
                            if let phone = client.phone {
                                Label(phone, systemImage: "phone")
                                    .font(.caption)
                            }
                            if let address = client.address {
                                Label(address, systemImage: "location")
                                    .font(.caption)
                            }
                            if let vatId = client.vatId {
                                Label("VAT: \(vatId)", systemImage: "doc.text")
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Projects
                GroupBox("Projects (\(clientProjects.count))") {
                    if clientProjects.isEmpty {
                        Text("No projects linked to this client")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(clientProjects) { project in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: project.colorHex) ?? .gray)
                                        .frame(width: 8, height: 8)
                                    Text(project.name)
                                        .font(.caption)
                                    Spacer()
                                    let usage = BudgetService.shared.budgetUsed(for: project.id, dataStore: dataStore)
                                    Text(Formatting.formatDuration(usage.timeUsed))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    EmptyView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Budget Summary
                let budgetUsage = BudgetService.shared.clientBudgetUsed(for: client.id, dataStore: dataStore)
                GroupBox("Budget Summary") {
                    HStack(spacing: 20) {
                        VStack {
                            Text(Formatting.formatDuration(budgetUsage.timeUsed))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Total Time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        VStack {
                            Text(String(format: "%.2f %@", budgetUsage.moneyUsed, client.currency))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Total Earned")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Invoices
                let clientInvoices = dataStore.invoices.filter { $0.clientId == client.id }
                if !clientInvoices.isEmpty {
                    GroupBox("Invoices (\(clientInvoices.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(clientInvoices) { invoice in
                                HStack {
                                    Text(invoice.invoiceNumber)
                                        .font(.caption)
                                    Spacer()
                                    Text(invoice.status.rawValue.capitalized)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(invoiceStatusColor(invoice.status).opacity(0.2))
                                        .cornerRadius(4)
                                    Text(String(format: "%.2f %@", invoice.totalAmount, invoice.currency))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 300)
    }

    private func invoiceStatusColor(_ status: InvoiceStatus) -> Color {
        switch status {
        case .draft: return .gray
        case .sent: return .blue
        case .paid: return .green
        case .overdue: return .red
        }
    }
}

// MARK: - Client Editor
struct ClientEditorView: View {
    let client: Client?
    let onSave: (Client) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var company = ""
    @State private var address = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var vatId = ""
    @State private var currency = "USD"
    @State private var defaultHourlyRate = ""
    @State private var defaultInvoiceNotes = ""
    @State private var archived = false

    private var isEditing: Bool { client != nil }

    private let currencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "CNY", "INR", "TRY"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Edit Client" : "New Client")
                .font(.title2)

            Form {
                TextField("Client Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Company", text: $company)
                    .textFieldStyle(.roundedBorder)
                TextField("Address", text: $address)
                    .textFieldStyle(.roundedBorder)
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                TextField("Phone", text: $phone)
                    .textFieldStyle(.roundedBorder)
                TextField("VAT ID", text: $vatId)
                    .textFieldStyle(.roundedBorder)

                Picker("Currency", selection: $currency) {
                    ForEach(currencies, id: \.self) { cur in
                        Text(cur).tag(cur)
                    }
                }

                HStack {
                    Text("Default Hourly Rate")
                    TextField("0.00", text: $defaultHourlyRate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                TextField("Default Invoice Notes", text: $defaultInvoiceNotes, axis: .vertical)
                    .lineLimit(3)

                if isEditing {
                    Toggle("Archived", isOn: $archived)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 450)
        .onAppear {
            if let client = client {
                name = client.name
                company = client.company ?? ""
                address = client.address ?? ""
                email = client.email ?? ""
                phone = client.phone ?? ""
                vatId = client.vatId ?? ""
                currency = client.currency
                defaultHourlyRate = client.defaultHourlyRate.map { String($0) } ?? ""
                defaultInvoiceNotes = client.defaultInvoiceNotes ?? ""
                archived = client.archived
            }
        }
    }

    private func save() {
        let rate = Double(defaultHourlyRate.replacingOccurrences(of: ",", with: "."))
        let newClient = Client(
            id: client?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            company: company.isEmpty ? nil : company,
            address: address.isEmpty ? nil : address,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            vatId: vatId.isEmpty ? nil : vatId,
            currency: currency,
            defaultHourlyRate: rate,
            defaultInvoiceNotes: defaultInvoiceNotes.isEmpty ? nil : defaultInvoiceNotes,
            archived: archived,
            createdAt: client?.createdAt ?? Date()
        )
        onSave(newClient)
    }
}
