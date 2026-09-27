import AppKit

/// Envoltorio mínimo de SkyLight (framework privado del Window Server) para mostrar una ventana
/// en la pantalla de bloqueo. Basado en Lakr233/SkyLightWindow (MIT).
///
/// Se crea un "espacio" a la altura de las notificaciones de la pantalla de bloqueo y se mueve
/// la ventana a él. Es una API privada: si falta algún símbolo, `isAvailable` es false y la
/// función se desactiva sola.
enum SkyLight {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock
    private static let lockScreenLevel: Int32 = 400

    private struct Functions {
        let mainConnectionID: MainConnectionID
        let spaceCreate: SpaceCreate
        let setLevel: SpaceSetAbsoluteLevel
        let showSpaces: ShowSpaces
        let addWindows: AddWindowsAndRemoveFromSpaces
    }

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let level = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return nil }
        return Functions(mainConnectionID: unsafeBitCast(main, to: MainConnectionID.self),
                         spaceCreate: unsafeBitCast(create, to: SpaceCreate.self),
                         setLevel: unsafeBitCast(level, to: SpaceSetAbsoluteLevel.self),
                         showSpaces: unsafeBitCast(show, to: ShowSpaces.self),
                         addWindows: unsafeBitCast(add, to: AddWindowsAndRemoveFromSpaces.self))
    }()

    private static var space: (connection: Int32, id: Int32)?

    static var isAvailable: Bool { functions != nil }

    /// Mueve la ventana al espacio de la pantalla de bloqueo (lo crea la primera vez).
    @discardableResult
    static func moveToLockScreen(_ window: NSWindow) -> Bool {
        guard let functions else { return false }
        if space == nil {
            let connection = functions.mainConnectionID()
            let id = functions.spaceCreate(connection, 1, 0)
            guard id != 0 else { return false }
            _ = functions.setLevel(connection, id, lockScreenLevel)
            // En macOS 27 SLSShowSpaces devuelve valores distintos de 0 aunque funcione: se ignora.
            _ = functions.showSpaces(connection, [id] as CFArray)
            space = (connection, id)
        }
        guard let space else { return false }
        _ = functions.addWindows(space.connection, space.id, [window.windowNumber] as CFArray, 7)
        return true
    }
}
