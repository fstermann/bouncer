import Darwin

/// Whether the active Space is a full screen app's, asked of SkyLight since no public call says.
///
/// Resolved at runtime, so a macOS release that drops a call reads as a desktop rather than crashing.
@MainActor
enum FullScreenSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32

    /// SkyLight's type for a full screen app's Space; a desktop is 0.
    private static let fullScreenType: Int32 = 4

    private static let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW
    )

    private static func call<T>(_ name: String, as type: T.Type) -> T? {
        dlsym(skyLight, name).map { unsafeBitCast($0, to: type) }
    }

    private static let mainConnection = call("SLSMainConnectionID", as: MainConnection.self)
    private static let activeSpace = call("SLSGetActiveSpace", as: ActiveSpace.self)
    private static let spaceType = call("SLSSpaceGetType", as: SpaceType.self)

    static var isActive: Bool {
        guard let mainConnection, let activeSpace, let spaceType else { return false }
        let connection = mainConnection()
        return spaceType(connection, activeSpace(connection)) == fullScreenType
    }
}
