import HealthKit

@MainActor
final class HeightProfile: ObservableObject {
    @Published private(set) var importedHeightCM: Double?
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    private let healthStore = HKHealthStore()

    func importHeight() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            message = "Apple Health ist auf diesem Gerät nicht verfügbar."
            return
        }

        isLoading = true
        message = nil

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [heightType])
            let height = try await newestHeight(for: heightType)
            if let height {
                importedHeightCM = height
                message = "Körpergröße aus Apple Health übernommen."
            } else {
                message = "In Apple Health wurde keine Körpergröße gefunden."
            }
        } catch {
            message = "Health-Daten konnten nicht gelesen werden: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func newestHeight(for type: HKQuantityType) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sample = samples?.first as? HKQuantitySample
                let centimeters = sample?.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: centimeters)
            }
            healthStore.execute(query)
        }
    }
}
