import SwiftUI
import PDFKit

struct InvoiceManagementView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var statusFilter: InvoiceStatus?
    @State private var showingCreateSheet = false
    @State private var selectedInvoice: Invoice?

    private var filteredInvoices: [Invoice] {
        let sorted = dataStore.invoices.sorted { $0.createdAt > $1.createdAt }
        guard let filter = statusFilter else { return sorted }
        return sorted.filter { $0.status == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .font(.title2)
                Text("Invoices")
                    .font(.title2)
                Spacer()

                // Status filter
                Picker("Status", selection: $statusFilter) {
                    Text("All").tag(InvoiceStatus?.none)
                    ForEach(InvoiceStatus.allCases, id: \.self) { status in
                        Text(status.rawValue.capitalized).tag(Optional(status))
                    }
                }
                .frame(width: 120)

                Button(action: { showingCreateSheet = true }) {
                    Label("New Invoice", systemImage: "plus")
                }
            }
            .padding()

            if filteredInvoices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Invoices")
                        .font(.headline)
                    Text("Create your first invoice from tracked sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredInvoices, selection: $selectedInvoice) { invoice in
                    InvoiceRowView(invoice: invoice)
                        .tag(invoice)
                        .contextMenu {
                            if invoice.status == .draft {
                                Button("Mark as Sent") { updateStatus(invoice, to: .sent) }
                            }
                            if invoice.status == .sent {
                                Button("Mark as Paid") { updateStatus(invoice, to: .paid) }
                                Button("Mark as Overdue") { updateStatus(invoice, to: .overdue) }
                            }
                            if invoice.status == .overdue {
                                Button("Mark as Paid") { updateStatus(invoice, to: .paid) }
                            }
                            Divider()
                            Button("Delete") { dataStore.deleteInvoice(invoice) }
                        }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            InvoiceCreatorView { invoice in
                dataStore.addInvoice(invoice)
                showingCreateSheet = false
            }
        }
    }

    private func updateStatus(_ invoice: Invoice, to status: InvoiceStatus) {
        var updated = invoice
        updated.status = status
        if status == .paid {
            updated.paidAt = Date()
        }
        dataStore.updateInvoice(updated)
    }
}

// MARK: - Invoice Row
struct InvoiceRowView: View {
    let invoice: Invoice
    @EnvironmentObject private var dataStore: LocalDataStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.invoiceNumber)
                    .fontWeight(.medium)
                Text(dataStore.clientName(for: invoice.clientId))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(invoice.status.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor(invoice.status).opacity(0.2))
                .foregroundColor(statusColor(invoice.status))
                .cornerRadius(6)

            Text(String(format: "%.2f %@", invoice.totalAmount, invoice.currency))
                .fontWeight(.medium)
                .frame(minWidth: 80, alignment: .trailing)

            let formatter = DateFormatter()
            Text({
                let f = DateFormatter()
                f.dateStyle = .short
                return f.string(from: invoice.createdAt)
            }())
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: InvoiceStatus) -> Color {
        switch status {
        case .draft: return .gray
        case .sent: return .blue
        case .paid: return .green
        case .overdue: return .red
        }
    }
}

// MARK: - Invoice Creator
struct InvoiceCreatorView: View {
    let onSave: (Invoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: LocalDataStore

    @State private var clientId: UUID?
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var notes = ""
    @State private var hourlyRate = ""
    @State private var taxRate = ""

    private var matchingSessions: [Session] {
        dataStore.sessions.filter { session in
            session.startTime >= startDate && session.endTime <= endDate && !session.isIdle && !session.isBreak
        }
    }

    private var totalHours: Double {
        matchingSessions.reduce(0) { $0 + $1.duration } / 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Invoice")
                .font(.title2)

            Form {
                Picker("Client", selection: $clientId) {
                    Text("No Client").tag(UUID?.none)
                    ForEach(dataStore.clients.filter { !$0.archived }) { client in
                        Text(client.name).tag(Optional(client.id))
                    }
                }

                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)

                HStack {
                    Text("Hourly Rate")
                    TextField("0.00", text: $hourlyRate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Tax Rate")
                    TextField("0", text: $taxRate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("%")
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3)

                // Preview
                GroupBox("Preview") {
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(matchingSessions.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Sessions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        VStack {
                            Text(String(format: "%.1f", totalHours))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Hours")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        VStack {
                            let rate = Double(hourlyRate) ?? 0
                            let subtotal = totalHours * rate
                            let tax = subtotal * (Double(taxRate) ?? 0) / 100
                            Text(String(format: "%.2f", subtotal + tax))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Total (\(dataStore.preferences.currency))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Invoice") { createInvoice() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(matchingSessions.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
        .onAppear {
            if let cId = clientId, let client = dataStore.clients.first(where: { $0.id == cId }) {
                hourlyRate = client.defaultHourlyRate.map { String($0) } ?? ""
                notes = client.defaultInvoiceNotes ?? ""
            }
            hourlyRate = dataStore.preferences.defaultHourlyRate.map { String($0) } ?? hourlyRate
        }
    }

    private func createInvoice() {
        let rate = Double(hourlyRate) ?? 0
        let subtotal = totalHours * rate
        let tax = subtotal * (Double(taxRate) ?? 0) / 100

        let invoice = Invoice(
            invoiceNumber: dataStore.nextInvoiceNumber(),
            clientId: clientId,
            status: .draft,
            dueDate: dueDate,
            totalAmount: subtotal + tax,
            taxAmount: tax,
            currency: dataStore.preferences.currency,
            notes: notes.isEmpty ? nil : notes,
            sessionIds: matchingSessions.map(\.id)
        )
        onSave(invoice)
    }
}
