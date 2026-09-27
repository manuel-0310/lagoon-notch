import Darwin
import Foundation
import IOKit
import Observation

/// CPU, memoria, GPU, red, disco y temperatura.
///
/// Solo mide mientras la pestaña Sistema está abierta (una muestra por segundo en una cola de
/// baja prioridad). Con la pestaña cerrada no hay ningún temporizador vivo.
@Observable
final class SystemMonitorService {
    static let historyLength = 60

    var cpu: Double = 0
    var cpuHistory: [Double] = []
    var coreCount = ProcessInfo.processInfo.activeProcessorCount
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var memoryHistory: [Double] = []
    var gpu: Double?
    var gpuHistory: [Double] = []
    var networkDown: Double = 0
    var networkUp: Double = 0
    var networkHistory: [Double] = []
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var temperature: Double?
    var thermalState: ProcessInfo.ThermalState = .nominal

    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private let queue = DispatchQueue(label: "app.lagoon.system", qos: .utility)
    @ObservationIgnored private let sampler = Sampler()

    var memoryFraction: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }

    var diskUsedFraction: Double {
        diskTotal > 0 ? 1 - Double(diskFree) / Double(diskTotal) : 0
    }

    // MARK: - Encendido solo con la pestaña visible

    func begin() {
        guard !AppEnvironment.isSnapshot else { return }
        viewers += 1
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func end() {
        guard !AppEnvironment.isSnapshot else { return }
        viewers = max(0, viewers - 1)
        guard viewers == 0, let timer else { return }
        timer.cancel()
        self.timer = nil
        sampler.reset()
    }

    private func tick() {
        let sample = sampler.sample()
        DispatchQueue.main.async { [weak self] in self?.apply(sample) }
    }

    private func apply(_ s: Sampler.Sample) {
        if let cpu = s.cpu {
            self.cpu = cpu
            Self.push(cpu, into: &cpuHistory)
        }
        memoryUsed = s.memoryUsed
        memoryTotal = s.memoryTotal
        Self.push(memoryFraction, into: &memoryHistory)
        gpu = s.gpu
        if let gpu = s.gpu { Self.push(gpu, into: &gpuHistory) }
        if let down = s.networkDown, let up = s.networkUp {
            networkDown = down
            networkUp = up
            Self.push(down, into: &networkHistory)
        }
        if let read = s.diskRead, let write = s.diskWrite {
            diskRead = read
            diskWrite = write
        }
        diskFree = s.diskFree
        diskTotal = s.diskTotal
        temperature = s.temperature
        thermalState = s.thermalState
    }

    private static func push(_ value: Double, into history: inout [Double]) {
        history.append(value)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }
}

// MARK: - Muestreo (fuera del hilo principal)

private final class Sampler {
    struct Sample {
        var cpu: Double?
        var memoryUsed: UInt64 = 0
        var memoryTotal: UInt64 = 0
        var gpu: Double?
        var networkDown: Double?
        var networkUp: Double?
        var diskRead: Double?
        var diskWrite: Double?
        var diskFree: Int64 = 0
        var diskTotal: Int64 = 0
        var temperature: Double?
        var thermalState: ProcessInfo.ThermalState = .nominal
    }

    private var previousTicks: [(busy: UInt64, total: UInt64)] = []
    private var previousNetwork: [String: (input: UInt32, output: UInt32)] = [:]
    private var previousNetworkDate: Date?
    private var previousDisk: (read: UInt64, write: UInt64, date: Date)?
    private var tick = 0
    private var lastTemperature: Double?
    private var lastDisk: (free: Int64, total: Int64) = (0, 0)
    private let sensors = TemperatureSensors()

    func reset() {
        previousTicks = []
        previousNetwork = [:]
        previousNetworkDate = nil
        previousDisk = nil
        tick = 0
    }

    func sample() -> Sample {
        var s = Sample()
        s.cpu = cpuUsage()
        (s.memoryUsed, s.memoryTotal) = memory()
        s.gpu = gpuUtilization()
        (s.networkDown, s.networkUp) = network()
        (s.diskRead, s.diskWrite) = diskIO()
        // Espacio libre y temperatura cambian despacio: cada 5 y 2 s.
        if tick % 5 == 0 { lastDisk = diskSpace() }
        (s.diskFree, s.diskTotal) = lastDisk
        if tick % 2 == 0 { lastTemperature = sensors.read() }
        s.temperature = lastTemperature
        s.thermalState = ProcessInfo.processInfo.thermalState
        tick += 1
        return s
    }

    // MARK: CPU

    private func cpuUsage() -> Double? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var ticks: [(busy: UInt64, total: UInt64)] = []
        for cpu in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * cpu
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            ticks.append((user + system + nice, user + system + nice + idle))
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return nil }
        var busy: UInt64 = 0, total: UInt64 = 0
        for (now, before) in zip(ticks, previousTicks) where now.total >= before.total {
            busy += now.busy &- before.busy
            total += now.total &- before.total
        }
        return total > 0 ? min(1, Double(busy) / Double(total)) : nil
    }

    // MARK: Memoria (como "Memoria usada" del Monitor de Actividad)

    private func memory() -> (UInt64, UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        let appMemory = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let used = (appMemory + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    // MARK: GPU (IOAccelerator → PerformanceStatistics)

    private func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue
                    ?? (stats["GPU Activity(%)"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, value / 100)
        }
        return best.map { min(1, max(0, $0)) }
    }

    // MARK: Red (bytes por segundo, sin contar la interfaz local)

    private func network() -> (Double?, Double?) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (nil, nil) }
        defer { freeifaddrs(pointer) }
        var current: [String: (input: UInt32, output: UInt32)] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            current[name] = (stats.ifi_ibytes, stats.ifi_obytes)
        }
        let now = Date()
        defer {
            previousNetwork = current
            previousNetworkDate = now
        }
        guard let before = previousNetworkDate else { return (nil, nil) }
        let elapsed = max(0.1, now.timeIntervalSince(before))
        var down: UInt64 = 0, up: UInt64 = 0
        for (name, value) in current {
            guard let old = previousNetwork[name] else { continue }
            // Los contadores son de 32 bits: la resta con desbordamiento cubre el salto a cero.
            down += UInt64(value.input &- old.input)
            up += UInt64(value.output &- old.output)
        }
        return (Double(down) / elapsed, Double(up) / elapsed)
    }

    // MARK: Disco

    private func diskIO() -> (Double?, Double?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return (nil, nil) }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
            else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        let now = Date()
        defer { previousDisk = (read, write, now) }
        guard let before = previousDisk, read >= before.read, write >= before.write else { return (nil, nil) }
        let elapsed = max(0.1, now.timeIntervalSince(before.date))
        return (Double(read - before.read) / elapsed, Double(write - before.write) / elapsed)
    }

    private func diskSpace() -> (Int64, Int64) {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values?.volumeTotalCapacity ?? 0))
    }
}

// MARK: - Temperatura (sensores HID, API privada de IOKit; en Apple Silicon)

/// Lee los sensores de temperatura con `IOHIDEventSystemClient`. Si las funciones no existen
/// (o no hay sensores), devuelve nil y la vista muestra el estado térmico público.
private final class TemperatureSensors {
    private typealias CreateFn = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> Int32
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloatFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeMutableRawPointer?

    private let copyServices: CopyServicesFn?
    private let copyEvent: CopyEventFn?
    private let getFloat: GetFloatFn?
    private let copyProperty: CopyPropertyFn?
    private var client: UnsafeMutableRawPointer?

    private static let temperatureEvent: Int64 = 15 // kIOHIDEventTypeTemperature
    private static var temperatureField: Int32 { Int32(15 << 16) }

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        let create = load("IOHIDEventSystemClientCreate", as: CreateFn.self)
        let setMatching = load("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self)
        copyServices = load("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self)
        copyEvent = load("IOHIDServiceClientCopyEvent", as: CopyEventFn.self)
        getFloat = load("IOHIDEventGetFloatValue", as: GetFloatFn.self)
        copyProperty = load("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self)

        guard let create, let setMatching, let client = create(nil) else { return }
        // Página 0xFF00, uso 5: sensores de temperatura de Apple.
        let matching = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, Unmanaged.passUnretained(matching).toOpaque())
        self.client = client
    }

    /// Temperatura del procesador en °C: media de los sensores de los núcleos ("tdie"), o el más
    /// alto razonable si no hay sensores con ese nombre.
    func read() -> Double? {
        guard let client, let copyServices, let copyEvent, let getFloat, let copyProperty,
              let servicesPointer = copyServices(client) else { return nil }
        let services = Unmanaged<CFArray>.fromOpaque(servicesPointer).takeRetainedValue()
        var dies: [Double] = []
        var others: [Double] = []
        let productKey = "Product" as CFString
        for index in 0..<CFArrayGetCount(services) {
            guard let service = CFArrayGetValueAtIndex(services, index),
                  let event = copyEvent(service, Self.temperatureEvent, 0, 0) else { continue }
            let value = getFloat(event, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(event).release()
            guard value > 5, value < 130 else { continue }
            var name = ""
            if let pointer = copyProperty(service, Unmanaged.passUnretained(productKey).toOpaque()) {
                name = (Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue() as? String) ?? ""
            }
            if name.localizedCaseInsensitiveContains("tdie") || name.localizedCaseInsensitiveContains("tp") && name.contains("CPU") {
                dies.append(value)
            } else {
                others.append(value)
            }
        }
        if !dies.isEmpty { return dies.reduce(0, +) / Double(dies.count) }
        return others.max()
    }
}
