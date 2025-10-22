import AppKit // this pretty much imports everything we need
import Carbon.HIToolbox.Events // keyCode values for NSEvent.keyCode

/// for pretty printing to console.
/// end with `ANSIColors.default_` to stop coloration.
enum ANSIColors: String {
    case black = "\u{001B}[0;30m"
    case red = "\u{001B}[0;31m"
    case green = "\u{001B}[0;32m"
    case yellow = "\u{001B}[0;33m"
    case blue = "\u{001B}[0;34m"
    case magenta = "\u{001B}[0;35m"
    case cyan = "\u{001B}[0;36m"
    case white = "\u{001B}[0;37m"
    case default_ = "\u{001B}[0;0m"
}

func + (left: String, right: ANSIColors) -> String {
    return left + right.rawValue
}

func + (left: ANSIColors, right: String) -> String {
    return left.rawValue + right + ANSIColors.default_
}

// define "db" functions (really we just store in xattrs of this file)
extension URL {
    /// get attribute.
    func extendedAttribute(forName name: String) throws -> Data {
        let data = try withUnsafeFileSystemRepresentation { fileSystemPath -> Data in
            let length = getxattr(fileSystemPath, name, nil, 0, 0, 0)
            guard length >= 0 else { throw URL.posixError(errno) }
            var data = Data(count: length)
            let result = data.withUnsafeMutableBytes { [count = data.count] in
                getxattr(fileSystemPath, name, $0.baseAddress, count, 0, 0)
            }
            guard result >= 0 else { throw URL.posixError(errno) }
            return data
        }
        return data
    }

    func setExtendedAttribute(data: Data, forName name: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = data.withUnsafeBytes {
                setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, 0)
            }
            guard result >= 0 else { throw URL.posixError(errno) }
        }
    }

    func removeExtendedAttribute(forName name: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = removexattr(fileSystemPath, name, 0)
            guard result >= 0 else { throw URL.posixError(errno) }
        }
    }

    /// get list of all attributes.
    func listExtendedAttributes() throws -> [String] {
        let list = try withUnsafeFileSystemRepresentation { fileSystemPath -> [String] in
            let length = listxattr(fileSystemPath, nil, 0, 0)
            guard length >= 0 else { throw URL.posixError(errno) }
            var namebuf = [CChar](repeating: 0, count: length)
            let result = listxattr(fileSystemPath, &namebuf, namebuf.count, 0)
            guard result >= 0 else { throw URL.posixError(errno) }
            let list = namebuf.split(separator: 0).compactMap {
                $0.withUnsafeBufferPointer {
                    $0.withMemoryRebound(to: UInt8.self) {
                        String(bytes: $0, encoding: .utf8)
                    }
                }
            }
            return list
        }
        return list
    }

    /// helper to create NSError from Unix errno.
    private static func posixError(_ err: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(err),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(err))])
    }
}

/// allows global persistent cursor control
enum CursorManager {
    // crazy this hack still works: https://stackoverflow.com/a/3939241
    /// enables background control of cursor
    static func enableBackgroundControl() {
        let handle = dlopen(nil, RTLD_LAZY)
        if let sym = dlsym(handle, "_CGSDefaultConnection") {
            typealias CGSDefaultConnectionFn = @convention(c) () -> Int32
            let cgsDefaultConnection = unsafeBitCast(sym, to: CGSDefaultConnectionFn.self)
            let connection = cgsDefaultConnection()
            if let setSym = dlsym(handle, "CGSSetConnectionProperty") {
                typealias CGSSetConnectionPropertyFn = @convention(c) (Int32, Int32, CFString, CFBoolean) -> CGError
                let cgsSetConnectionProperty = unsafeBitCast(setSym, to: CGSSetConnectionPropertyFn.self)
                let key = "SetsCursorInBackground" as CFString
                _ = cgsSetConnectionProperty(connection, connection, key, kCFBooleanTrue)
            }
        }
    }

    /// hide system cursor
    static func hide() {
        CGDisplayHideCursor(CGMainDisplayID())
    }

    /// show system cursor
    static func show() {
        CGDisplayShowCursor(CGMainDisplayID())
    }
}

/// encodable colors as proxy to NSColor
enum Color: Codable {
    case green, brown, yellow

    func getNSColor() -> NSColor {
        switch self {
        case .green:
            NSColor.green
        case .brown:
            NSColor.brown
        case .yellow:
            NSColor.yellow
        }
    }
}

/// also acts as mapping from emoji case -> emoji string
enum EmojiMap: String, Codable {
    case hamster = "🐹",
         grass = "🌱",
         handPointFinger = "👆"

    func getString() -> String {
        return rawValue
    }

    static func getString(_ emoji: EmojiMap) -> String {
        return emoji.rawValue
    }
}

/// states of dynamic entities for state machine
enum DynamicEntityState: Codable {
    case idle,
         chasingCursor,
         persuingTarget(Double, Double),
         consumingTarget(Double)
}

struct StaticEntityData: Codable {
    var plantable: Bool
    var emoji: EmojiMap
    var fontSize: CGFloat
    var foregroundColor: Color
    var position: CGPoint
}

struct DynamicEntityData: Codable {
    var plantable: Bool
    var emoji: EmojiMap
    var fontSize: CGFloat
    var foregroundColor: Color
    var position: CGPoint
    var moveSpeed: CGFloat // pixels per second
    var dynamicEntityState: DynamicEntityState
}

/// should be empty.
/// its purpose is enforcing `Codable` on everything that inherits from it
class Entity: Codable {}

class StaticEntity: Entity {
    var data: StaticEntityData

    enum CodingKeys: String, CodingKey {
        case data
    }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(StaticEntityData.self, forKey: .data)
        try super.init(from: decoder)
    }

    required init(data_: StaticEntityData) {
        data = data_
        super.init()
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try super.encode(to: encoder)
    }

    func draw() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: data.fontSize),
            .foregroundColor: data.foregroundColor.getNSColor(),
        ]
        let string = NSAttributedString(string: data.emoji.getString(), attributes: attrs)
        let rect = NSRect(
            x: data.position.x - data.fontSize / 2,
            y: data.position.y - data.fontSize / 2,
            width: data.fontSize,
            height: data.fontSize
        )
        string.draw(in: rect)
    }
}

class DynamicEntity: Entity {
    var data: DynamicEntityData

    enum CodingKeys: String, CodingKey {
        case data
    }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(DynamicEntityData.self, forKey: .data)
        try super.init(from: decoder)
    }

    required init(data_: DynamicEntityData) {
        data = data_
        super.init()
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try super.encode(to: encoder)
    }

    func draw() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: data.fontSize),
            .foregroundColor: data.foregroundColor.getNSColor(),
        ]
        let string = NSAttributedString(string: data.emoji.getString(), attributes: attrs)
        let rect = NSRect(
            x: data.position.x - data.fontSize / 2,
            y: data.position.y - data.fontSize / 2,
            width: data.fontSize,
            height: data.fontSize
        )
        string.draw(in: rect)
    }

    /// empty method.
    /// override in inherited class if need update logic
    func animate(_: EnvironmentData) {}
}

/// nessesary for preserving polymorphism when decoding
struct PolymorphicStaticEntity: Codable {
    let entity: StaticEntity

    private enum EntityType: Codable {
        case staticEntity,
             grass
    }

    private enum CodingKeys: CodingKey {
        case type,
             data
    }

    init(entity: StaticEntity) {
        self.entity = entity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EntityType.self, forKey: .type)
        let data = try container.decode(StaticEntityData.self, forKey: .data)

        switch type {
        case .staticEntity:
            entity = StaticEntity(data_: data)
        case .grass:
            entity = Grass(data_: data)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(getType(for: entity), forKey: .type)
        try container.encode(entity.data, forKey: .data)
    }

    private func getType(for entity: StaticEntity) -> EntityType {
        switch entity {
        case is Grass:
            return .grass
        default:
            return .staticEntity
        }
    }
}

/// nessesary for preserving polymorphism when decoding
struct PolymorphicDynamicEntity: Codable {
    let entity: DynamicEntity

    private enum EntityType: Codable {
        case dynamicEntity,
             hamster
    }

    private enum CodingKeys: CodingKey {
        case type,
             data
    }

    init(entity: DynamicEntity) {
        self.entity = entity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EntityType.self, forKey: .type)
        let data = try container.decode(DynamicEntityData.self, forKey: .data)

        switch type {
        case .dynamicEntity:
            entity = DynamicEntity(data_: data)
        case .hamster:
            entity = Hamster(data_: data)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(getType(for: entity), forKey: .type)
        try container.encode(entity.data, forKey: .data)
    }

    private func getType(for entity: DynamicEntity) -> EntityType {
        switch entity {
        case is Hamster:
            return .hamster
        default:
            return .dynamicEntity
        }
    }
}

/// onforces static initializer implementation for entities
/// that inherit from `DynamicEntity` or `StaticEntity`.
protocol DerivedEntity {
    static func create() -> Self
}

class Hamster: DynamicEntity, DerivedEntity {
    static func create() -> Self {
        let hamsterData = DynamicEntityData(
            plantable: false,
            emoji: EmojiMap.hamster,
            fontSize: 20,
            foregroundColor: Color.brown,
            position: CGPoint(x: 0, y: 0),
            moveSpeed: 100,
            dynamicEntityState: .idle
        )

        return self.init(data_: hamsterData)
    }

    override func animate(_ env: EnvironmentData) {
        // animation cases
        switch data.dynamicEntityState {
        case .chasingCursor:
            let dx = env.cursor.data.position.x - data.position.x
            let dy = env.cursor.data.position.y - data.position.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance > 2.0 {
                // still moving
                let speedThisFrame = data.moveSpeed * CGFloat(env.deltaTime)
                let moveDist = min(speedThisFrame, distance)
                let moveX = (dx / distance) * moveDist
                let moveY = (dy / distance) * moveDist
                data.position.x += moveX
                data.position.y += moveY
            }
        case let .persuingTarget(x, y):
            let dx = x - data.position.x
            let dy = y - data.position.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance > 2.0 {
                // still moving
                let speedThisFrame = data.moveSpeed * CGFloat(env.deltaTime)
                let moveDist = min(speedThisFrame, distance)
                let moveX = (dx / distance) * moveDist
                let moveY = (dy / distance) * moveDist
                data.position.x += moveX
                data.position.y += moveY
            } else {
                // arrived
                data.dynamicEntityState = .consumingTarget(2.0)
            }
        case let .consumingTarget(t):
            let newTime = t - env.deltaTime
            data.dynamicEntityState = .consumingTarget(newTime)
            if newTime < 0 {
                data.dynamicEntityState = .idle
            }
        case .idle: break
        }
    }
}

class Grass: StaticEntity, DerivedEntity {
    static func create() -> Self {
        let grassData = StaticEntityData(
            plantable: true,
            emoji: EmojiMap.grass,
            fontSize: 20,
            foregroundColor: Color.green,
            position: CGPoint(x: 0, y: 0)
        )

        return self.init(data_: grassData)
    }
}

struct EnvironmentData: Codable {
    var polymorphicStaticEntities: [PolymorphicStaticEntity]
    var polymorphicDynamicEntities: [PolymorphicDynamicEntity]
    var cursor: StaticEntity = .init(
        data_: StaticEntityData(
            plantable: false,
            emoji: EmojiMap.handPointFinger,
            fontSize: 20,
            foregroundColor: Color.yellow,
            position: CGPoint(x: 0, y: 0)
        )
    )
    var deltaTime: CGFloat = 0

    func draw() {
        for wrapped in polymorphicStaticEntities {
            wrapped.entity.draw()
        }

        for wrapped in polymorphicDynamicEntities {
            wrapped.entity.draw()
        }

        cursor.draw()
    }

    mutating func animate(_ deltaTime_: CGFloat) {
        deltaTime = deltaTime_
        for wrapped in polymorphicDynamicEntities {
            wrapped.entity.animate(self)
        }
    }
}

class EnvironmentView: NSView {
    private var _env: EnvironmentData
    var env: EnvironmentData {
        return _env
    }

    // animation
    /// syncs fps with monitor refresh rate
    private var __displayLink: CADisplayLink!
    private var lastCursorHideTime: CFTimeInterval = -1

    init(frame frameRect: NSRect, environmentData_: EnvironmentData) {
        _env = environmentData_

        // create hamster for testing
        let hamster = Hamster.create()
        hamster.data.position = CGPoint(x: frameRect.width / 2, y: frameRect.height - 10)
        hamster.data.dynamicEntityState = .chasingCursor

        _env.polymorphicDynamicEntities.append(PolymorphicDynamicEntity(entity: hamster))

        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        _env.draw()
    }

    func startAnimation() {
        __displayLink = displayLink(target: self, selector: #selector(animationTick))
        __displayLink.preferredFrameRateRange = .init(minimum: 60, maximum: 120, preferred: 60)
        __displayLink.add(to: .main, forMode: .default)
    }

    @objc private func animationTick(displayLink_: CADisplayLink) {
        // poll mouse position
        let mouseGlobalPoint = NSEvent.mouseLocation
        let mouseLocalPoint = convert(mouseGlobalPoint, from: nil)
        _env.cursor.data.position = mouseLocalPoint

        let deltaTime = displayLink_.targetTimestamp - displayLink_.timestamp
        _env.animate(deltaTime)

        // periodically hide system cursor
        let now = CACurrentMediaTime()
        if now - lastCursorHideTime > 0.05 {
            CursorManager.hide()
            lastCursorHideTime = now
        }

        setNeedsDisplay(bounds)
    }

    func updateMousePosition(to point: NSPoint) {
        _env.cursor.data.position = point
    }

    // Public: Add grass at click position, distract hamster
    // func addGrass(at point: NSPoint) {
    //    // Add to visible grasses (avoid exact dupes)
    //    if !grasses.contains(point) {
    //        grasses.append(point)
    //    }
    //    // Add to pending queue
    //    pendingGrasses.append(point)
    //    setNeedsDisplay(bounds)
    //    processNextGrassIfIdle()
    // }

    // Remove specific grass
    // private func removeGrass(at point: NSPoint) {
    //    if let index = grasses.firstIndex(where: { $0 == point }) {
    //        grasses.remove(at: index)
    //    }
    //    setNeedsDisplay(bounds)
    // }

    override var isOpaque: Bool { false }

    deinit {
        __displayLink.invalidate()
        __displayLink = nil
        CursorManager.show()
    }
}

// get the script's own URL
let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let scriptURL = URL(fileURLWithPath: #file, relativeTo: cwdURL)

let gameStateSaveKey = "com.hamster.gameState.jsonEnvData"

func loadGameState() -> EnvironmentData {
    var envData: EnvironmentData
    do {
        let jsonEnvData = try scriptURL.extendedAttribute(forName: gameStateSaveKey)
        print(ANSIColors.green + "Loaded save successfully)")
        envData = try JSONDecoder().decode(EnvironmentData.self, from: jsonEnvData)
    } catch {
        print(ANSIColors.cyan + "No save found, starting new game...")
        envData = EnvironmentData(polymorphicStaticEntities: [], polymorphicDynamicEntities: [])
    }
    return envData
}

func saveGameState(env: EnvironmentData) {
    do {
        let jsonEnvData = try JSONEncoder().encode(env)
        try scriptURL.setExtendedAttribute(data: jsonEnvData, forName: gameStateSaveKey)
        print(ANSIColors.green + "Saved progress successfully)")
    } catch {
        print(ANSIColors.red + "Save failed, progress might be lost!")
    }
}

let screen = NSScreen.main ?? NSScreen.screens[0]
let contentRect = screen.frame

let envData = loadGameState()
let environmentView = EnvironmentView(
    frame: contentRect,
    environmentData_: envData
)

let window = NSWindow(
    contentRect: contentRect,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
window.backgroundColor = NSColor.clear
window.isOpaque = false
window.hasShadow = false
window.ignoresMouseEvents = true // passthrough enabled
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
window.contentView = environmentView
window.makeKeyAndOrderFront(nil)

CursorManager.enableBackgroundControl()
CursorManager.hide()

// global left-click monitor for grass
// let clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
//    let globalPoint = NSEvent.mouseLocation
//    let localPoint = environmentView.convert(globalPoint, from: nil)
//    environmentView.addGrass(at: localPoint)
// }

var lastEscPress = -1.0
// global key monitor for keyboard presses
let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == kVK_Escape, !event.isARepeat {
        let time = Date.timeIntervalSinceReferenceDate
        if time - lastEscPress < 0.7 {
            saveGameState(env: environmentView.env)

            CursorManager.show()
//            NSEvent.removeMonitor(clickMonitor!)
            NSEvent.removeMonitor(keyMonitor!)
            NSApplication.shared.terminate(nil)
        }
        lastEscPress = time
    }
}

// set initial mouse position to avoid starting at (0,0)
let initialGlobalPoint = NSEvent.mouseLocation
let initialLocalPoint = environmentView.convert(initialGlobalPoint, from: nil)
environmentView.updateMousePosition(to: initialLocalPoint)
// start animation after setup
environmentView.startAnimation()

// start the app
let app = NSApplication.shared
app.run()
