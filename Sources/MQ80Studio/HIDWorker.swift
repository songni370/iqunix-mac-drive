import Foundation

/// Everything the UI needs right after connecting.
struct ConnectionSnapshot {
    let info: DeviceInfo
    let keymap: Keymap
    let lighting: LightingState
}

/// Wraps `VIAController` so the controller is created, used and closed on one
/// dedicated serial queue. Callbacks are always delivered on the main thread.
final class HIDWorker {
    private let queue = DispatchQueue(label: "studio.mq80.hid", qos: .userInitiated)
    private var controller: VIAController?

    // MARK: Delivery

    private func deliver<T>(_ value: T, to completion: @escaping (T) -> Void) {
        DispatchQueue.main.async { completion(value) }
    }

    private func fail<T>(_ error: Error, to completion: @escaping (Result<T, Error>) -> Void) {
        deliver(.failure(error), to: completion)
    }

    private func deliverProgress(_ progress: @escaping (Double) -> Void, _ value: Double) {
        DispatchQueue.main.async { progress(value) }
    }

    // MARK: Discovery (read-only, never opens the device)

    func discover(_ completion: @escaping ([VIADevice]) -> Void) {
        queue.async {
            let devices = VIADiscovery.find()
            self.deliver(devices, to: completion)
        }
    }

    // MARK: Connection

    func connect(device: VIADevice, definition: KeyboardDefinition, completion: @escaping (Result<ConnectionSnapshot, Error>) -> Void) {
        queue.async {
            if let existing = self.controller {
                existing.close()
                self.controller = nil
            }
            var opened: VIAController?
            do {
                let controller = try VIAController.open(device: device, definition: definition)
                opened = controller
                let keymap = try controller.readKeymap()
                let lighting = try controller.readLighting()
                self.controller = controller
                self.deliver(
                    .success(ConnectionSnapshot(info: controller.info, keymap: keymap, lighting: lighting)),
                    to: completion
                )
            } catch {
                (opened ?? self.controller)?.close()
                self.controller = nil
                self.fail(error, to: completion)
            }
        }
    }

    func disconnect(completion: (() -> Void)? = nil) {
        queue.async {
            self.controller?.close()
            self.controller = nil
            if let completion = completion {
                DispatchQueue.main.async { completion() }
            }
        }
    }

    // MARK: Keymap

    func writeKeymap(
        _ keymap: Keymap,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Keymap, Error>) -> Void
    ) {
        queue.async {
            guard let controller = self.controller else {
                self.fail(VIAError.notConnected, to: completion)
                return
            }
            do {
                try controller.writeKeymap(keymap, verify: true) { value in
                    self.deliverProgress(progress, value)
                }
                let readBack = try controller.readKeymap()
                self.deliver(.success(readBack), to: completion)
            } catch {
                self.fail(error, to: completion)
            }
        }
    }

    func readKeymap(completion: @escaping (Result<Keymap, Error>) -> Void) {
        queue.async {
            guard let controller = self.controller else {
                self.fail(VIAError.notConnected, to: completion)
                return
            }
            do {
                self.deliver(.success(try controller.readKeymap()), to: completion)
            } catch {
                self.fail(error, to: completion)
            }
        }
    }

    // MARK: Lighting

    func readLighting(completion: @escaping (Result<LightingState, Error>) -> Void) {
        queue.async {
            guard let controller = self.controller else {
                self.fail(VIAError.notConnected, to: completion)
                return
            }
            do {
                self.deliver(.success(try controller.readLighting()), to: completion)
            } catch {
                self.fail(error, to: completion)
            }
        }
    }

    func applyLighting(
        _ state: LightingState,
        completion: @escaping (Result<LightingState, Error>) -> Void
    ) {
        queue.async {
            guard let controller = self.controller else {
                self.fail(VIAError.notConnected, to: completion)
                return
            }
            do {
                try controller.applyLighting(state, verify: true)
                let readBack = try controller.readLighting()
                self.deliver(.success(readBack), to: completion)
            } catch {
                self.fail(error, to: completion)
            }
        }
    }

    // MARK: Backup / restore

    func createBackup(directory: URL? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            guard let controller = self.controller else {
                self.fail(VIAError.notConnected, to: completion)
                return
            }
            do {
                let keymap = try controller.readKeymap()
                let lighting = try controller.readLighting()
                let backup = KeyboardBackup(controller: controller, keymap: keymap, lighting: lighting, macros: nil)
                let url = try BackupStore.save(backup, directory: directory)
                self.deliver(.success(url), to: completion)
            } catch {
                self.fail(error, to: completion)
            }
        }
    }

    func restore(
        _ backup: KeyboardBackup,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<ConnectionSnapshot, Error>) -> Void
    ) {
        queue.async {
            guard let controller = self.controller else {
                self.fail(VIAError.notConnected, to: completion)
                return
            }
            do {
                try controller.writeKeymap(backup.keymap, verify: true) { value in
                    self.deliverProgress(progress, value)
                }
                if let lighting = backup.lighting {
                    try controller.applyLighting(lighting, verify: true)
                }
                let keymap = try controller.readKeymap()
                let lighting = try controller.readLighting()
                self.deliver(
                    .success(ConnectionSnapshot(info: controller.info, keymap: keymap, lighting: lighting)),
                    to: completion
                )
            } catch {
                self.fail(error, to: completion)
            }
        }
    }
}
