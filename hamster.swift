import AppKit // this pretty much imports everything we need
import Carbon.HIToolbox.Events // keyCode values for NSEvent.keyCode

/// for pretty printing to console.
/// end with `ANSIColors.default_` to stop coloration.
enum ANSIColors: String {
    case black = "\u{001B}[0;30m"
    /// error color
    case red = "\u{001B}[0;31m"
    /// success color
    case green = "\u{001B}[0;32m"
    /// warning color
    case yellow = "\u{001B}[0;33m"
    /// information color
    case blue = "\u{001B}[0;34m"
    case magenta = "\u{001B}[0;35m"
    case cyan = "\u{001B}[0;36m"
    case white = "\u{001B}[0;37m"
    /// default terminal colors
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

enum CursorInteractionState: Codable {
    case none, cursorOver
}

struct StaticEntityData: Codable {
    var plantable: Bool
    var emoji: EmojiMap
    var fontSize: CGFloat
    var foregroundColor: Color
    var position: CGPoint
    var cursorInteractionState: CursorInteractionState = .none
}

struct DynamicEntityData: Codable {
    var plantable: Bool
    var emoji: EmojiMap
    var fontSize: CGFloat
    var foregroundColor: Color
    var position: CGPoint
    var moveSpeed: CGFloat // pixels per second
    var dynamicEntityState: DynamicEntityState
    var cursorInteractionState: CursorInteractionState = .none
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
        // if cursor is over, just for this frame increase font size
        if data.cursorInteractionState == .cursorOver {
            data.fontSize += 6
        }

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

        if data.cursorInteractionState == .cursorOver {
            data.fontSize -= 6
            data.cursorInteractionState = .none
        }
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
        // if cursor is over, just for this frame increase font size
        if data.cursorInteractionState == .cursorOver {
            data.fontSize += 6
        }

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

        if data.cursorInteractionState == .cursorOver {
            data.fontSize -= 6
            data.cursorInteractionState = .none
        }
    }

    /// empty method.
    /// override in inherited class if it updates logic
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

/// type union for different types of polymorphic entities
enum PolymorphicEntity: Codable {
    case dynamic_(PolymorphicDynamicEntity),
         static_(PolymorphicStaticEntity)

    func getPosition() -> CGPoint {
        switch self {
        case let .dynamic_(ent):
            ent.entity.data.position
        case let .static_(ent):
            ent.entity.data.position
        }
    }

    func setPosition(position: CGPoint) {
        switch self {
        case let .dynamic_(ent):
            ent.entity.data.position = position
        case let .static_(ent):
            ent.entity.data.position = position
        }
    }

    func setFontSize(fontSize: CGFloat) {
        switch self {
        case let .dynamic_(ent):
            ent.entity.data.fontSize = fontSize
        case let .static_(ent):
            ent.entity.data.fontSize = fontSize
        }
    }

    func setCursorInteractionState(_ state: CursorInteractionState) {
        switch self {
        case let .dynamic_(ent):
            ent.entity.data.cursorInteractionState = state
        case let .static_(ent):
            ent.entity.data.cursorInteractionState = state
        }
    }

    func draw() {
        switch self {
        case let .dynamic_(ent): ent.entity.draw()
        case let .static_(ent): ent.entity.draw()
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
            fontSize: 28,
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
            let cursorPosition = env.cursor.getPosition()
            let dx = cursorPosition.x - data.position.x
            let dy = cursorPosition.y - data.position.y
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
            fontSize: 28,
            foregroundColor: Color.green,
            position: CGPoint(x: 0, y: 0)
        )

        return self.init(data_: grassData)
    }
}

/// stores and manages items
struct ItemDrawer: Codable {
    var bottomLeftCorner: CGPoint = .init(x: 100, y: 100)
    var fontSize: CGFloat = 28
    var entityTable: [[PolymorphicEntity?]] = [[nil, nil, nil, nil, nil]]

    func getRows() -> Int {
        return entityTable.count
    }

    func getCols() -> Int {
        if entityTable.count > 0 {
            return entityTable[0].count
        }
        return 0
    }

    mutating func addItem(_ polymorphicEntity: PolymorphicEntity) {
        // find free spot in the table
        var freeX: Int = -1
        var freeY: Int = -1
        freeSpotSearch: do {
            for y in 0 ... entityTable.count - 1 {
                for x in 0 ... entityTable[y].count - 1 {
                    switch entityTable[y][x] {
                    case nil:
                        freeX = x
                        freeY = y
                        break freeSpotSearch
                    case _: break
                    }
                }
            }
        }

        if freeX != -1 {
            // update entity show up in drawer properly
            let posX = bottomLeftCorner.x + CGFloat(freeX) * fontSize + fontSize / 2
            let posY = bottomLeftCorner.y + CGFloat(freeY) * fontSize + fontSize / 2
            polymorphicEntity.setPosition(position: .init(
                x: posX,
                y: posY
            ))
            polymorphicEntity.setFontSize(fontSize: fontSize)
            entityTable[freeY][freeX] = polymorphicEntity
        } else {
            // TODO: table full, play operation unsuccessfull [sound]
            print(ANSIColors.yellow + "Drawer full, can't place item!")
        }
    }

    func draw() {
        for row in entityTable {
            for item in row {
                item?.draw()
            }
        }
    }
}

let defaultCursor: StaticEntity = .init(
    data_: StaticEntityData(
        plantable: false,
        emoji: EmojiMap.handPointFinger,
        fontSize: 28,
        foregroundColor: Color.yellow,
        position: CGPoint(x: 0, y: 0)
    )
)

struct EnvironmentData: Codable {
    var polymorphicStaticEntities: [PolymorphicStaticEntity] = []
    var polymorphicDynamicEntities: [PolymorphicDynamicEntity] = []
    var cursor: PolymorphicEntity = .static_(PolymorphicStaticEntity(entity: defaultCursor))
    var deltaTime: CGFloat = 0
    var itemDrawer: ItemDrawer = .init()

    func draw() {
        for wrapped in polymorphicStaticEntities {
            wrapped.entity.draw()
        }

        for wrapped in polymorphicDynamicEntities {
            wrapped.entity.draw()
        }

        itemDrawer.draw()

        cursor.draw()
    }

    mutating func animate(_ deltaTime_: CGFloat) {
        deltaTime = deltaTime_
        for wrapped in polymorphicDynamicEntities {
            wrapped.entity.animate(self)
        }

        // if cursor over itemDrawer, set proper cursorInteractionState on item
        let point = cursor.getPosition()
        let start = itemDrawer.bottomLeftCorner
        let rows = itemDrawer.getRows()
        let cols = itemDrawer.getCols()
        let fontSize = itemDrawer.fontSize

        let width = CGFloat(cols) * fontSize
        let height = CGFloat(rows) * fontSize

        let pTransform = CGPoint(x: point.x - start.x, y: point.y - start.y)
        if pTransform.x >= 0, pTransform.x < width, pTransform.y >= 0, pTransform.y < height {
            let cellNumX = Int(pTransform.x / fontSize)
            let cellNumY = Int(pTransform.y / fontSize)

            if let _ = itemDrawer.entityTable[cellNumY][cellNumX] {
                // set interaction state
                itemDrawer.entityTable[cellNumY][cellNumX]?.setCursorInteractionState(.cursorOver)
            }
        }
    }

    mutating func processClick(at point: CGPoint) {
        // 1. check intersection with a drawer
        let start = itemDrawer.bottomLeftCorner
        let rows = itemDrawer.getRows()
        let cols = itemDrawer.getCols()
        let fontSize = itemDrawer.fontSize

        let width = CGFloat(cols) * fontSize
        let height = CGFloat(rows) * fontSize

        let pTransform = CGPoint(x: point.x - start.x, y: point.y - start.y)
        if pTransform.x >= 0, pTransform.x < width, pTransform.y >= 0, pTransform.y < height {
            // click inside drawer
            let cellNumX = Int(pTransform.x / fontSize)
            let cellNumY = Int(pTransform.y / fontSize)

            if let pickedItem = itemDrawer.entityTable[cellNumY][cellNumX] {
                // add to hand and remove from drawer
                cursor = pickedItem
                itemDrawer.entityTable[cellNumY][cellNumX] = nil
            }

            return
        }

        // 2. check intersection with entities in environment

        // 3. check if can place item
    }
}

/// provides view over EnvironmentData and manages gameloop / syncing
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
        // let hamster = Hamster.create()
        // hamster.data.position = CGPoint(x: frameRect.width / 2, y: frameRect.height - 10)
        // hamster.data.dynamicEntityState = .chasingCursor
        // _env.polymorphicDynamicEntities.append(PolymorphicDynamicEntity(entity: hamster))

        // create items for drawer testing
        let grasses = (0 ... 5).map { _ in
            Grass.create()
        }
        for grass in grasses {
            _env.itemDrawer.addItem(.static_(PolymorphicStaticEntity(entity: grass)))
        }

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
        _env.cursor.setPosition(position: mouseLocalPoint)

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

    func updateMousePosition(to point: CGPoint) {
        _env.cursor.setPosition(position: point)
    }

    func handleClick(at point: CGPoint) {
        _env.processClick(at: point)
    }

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

let gameStateSaveKey = "com.hamster.gameState.jsonEnvData#S"

func saveGameState(env: EnvironmentData) {
    do {
        let jsonEnvData = try JSONEncoder().encode(env)
        try scriptURL.setExtendedAttribute(data: jsonEnvData, forName: gameStateSaveKey)
        print(ANSIColors.green + "Saved progress successfully)")
    } catch {
        print(ANSIColors.red + "Save failed, progress might be lost!")
    }
}

func loadGameState() -> EnvironmentData {
    var envData: EnvironmentData
    do {
        let jsonEnvData = try scriptURL.extendedAttribute(forName: gameStateSaveKey)
        print(ANSIColors.green + "Loaded save successfully)")
        envData = try JSONDecoder().decode(EnvironmentData.self, from: jsonEnvData)
    } catch {
        print(ANSIColors.blue + "No save found, starting new game...")
        envData = EnvironmentData()
    }
    return envData
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

// global left-click monitor
let clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
    let globalPoint = NSEvent.mouseLocation
    let localPoint = environmentView.convert(globalPoint, from: nil)
    environmentView.handleClick(at: localPoint)
}

var lastEscPress = -1.0
// global keypress monitor
let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == kVK_Escape, !event.isARepeat {
        let time = Date.timeIntervalSinceReferenceDate
        if time - lastEscPress < 0.7 {
            saveGameState(env: environmentView.env)

            CursorManager.show()
            NSEvent.removeMonitor(clickMonitor!)
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
