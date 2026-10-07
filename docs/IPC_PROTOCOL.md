# CyberMod Studio - IPC Protocol Specification

## 1. Overview

The IPC (Inter-Process Communication) protocol connects **CyberMod Studio** (macOS app) directly to the
**DebugAgent** (an in-game RED4ext plugin). There is no helper daemon: Studio launches the game itself
(see `GameLauncher`) and talks to the agent over a socket.

## 2. Transport: Unix Domain Socket

Uses a Unix domain socket for high-performance, low-latency communication.

```
Socket Path: /tmp/cybermod-debug-{pid}.sock
Protocol: Binary framed messages
```

## 3. Message Format

### 3.1 Frame Structure

```
┌─────────────────────────────────────────────────────────────────┐
│  Magic (4 bytes)  │  Version (2)  │  Type (2)  │  Length (4)   │
├─────────────────────────────────────────────────────────────────┤
│                        Payload (variable)                       │
├─────────────────────────────────────────────────────────────────┤
│                        Checksum (4 bytes)                       │
└─────────────────────────────────────────────────────────────────┘

Magic:    0x43594D44 ("CYMD")
Version:  0x0001
Type:     Message type identifier
Length:   Payload length in bytes (big-endian)
Payload:  MessagePack-encoded data
Checksum: CRC32 of header + payload
```

### 3.2 Message Types

```swift
enum MessageType: UInt16 {
    // Connection
    case handshake          = 0x0001
    case handshakeAck       = 0x0002
    case heartbeat          = 0x0003
    case disconnect         = 0x0004
    
    // TweakDB Operations
    case tweakDBList        = 0x0100
    case tweakDBListResp    = 0x0101
    case tweakDBGet         = 0x0102
    case tweakDBGetResp     = 0x0103
    case tweakDBSet         = 0x0104
    case tweakDBSetResp     = 0x0105
    case tweakDBSearch      = 0x0106
    case tweakDBSearchResp  = 0x0107
    
    // Hook Operations
    case hookList           = 0x0200
    case hookListResp       = 0x0201
    case hookStats          = 0x0202
    case hookStatsResp      = 0x0203
    case hookEnable         = 0x0204
    case hookDisable        = 0x0205
    case hookAck            = 0x0206
    
    // Plugin Operations
    case pluginList         = 0x0300
    case pluginListResp     = 0x0301
    case pluginInfo         = 0x0302
    case pluginInfoResp     = 0x0303
    
    // Memory Operations
    case memoryRead         = 0x0400
    case memoryReadResp     = 0x0401
    case memoryRegions      = 0x0402
    case memoryRegionsResp  = 0x0403
    
    // Address Operations
    case addressResolve     = 0x0500
    case addressResolveResp = 0x0501
    case addressValidate    = 0x0502
    case addressValidateResp= 0x0503
    
    // Log Operations
    case logSubscribe       = 0x0600
    case logUnsubscribe     = 0x0601
    case logEntry           = 0x0602
    
    // Error
    case error              = 0xFFFF
}
```

## 4. Message Definitions

### 4.1 Connection Messages

#### Handshake (0x0001)

```swift
struct HandshakeMessage: Codable {
    let protocolVersion: UInt16  // 1
    let clientName: String       // "CyberModStudio"
    let clientVersion: String    // "1.0.0"
    let capabilities: [String]   // ["tweakdb", "hooks", "memory"]
}
```

#### HandshakeAck (0x0002)

```swift
struct HandshakeAckMessage: Codable {
    let accepted: Bool
    let serverName: String       // "DebugAgent"
    let serverVersion: String    // "1.0.0"
    let gameVersion: String      // "2.21"
    let capabilities: [String]   // Supported capabilities
    let sessionId: UUID
}
```

### 4.2 TweakDB Messages

#### TweakDBList (0x0100)

```swift
struct TweakDBListRequest: Codable {
    let filter: TweakDBFilter?
    let offset: Int
    let limit: Int
}

struct TweakDBFilter: Codable {
    let recordType: String?      // e.g., "gamedataItem_Record"
    let namePattern: String?     // Regex pattern
    let modifiedOnly: Bool?      // Only show modified values
}
```

#### TweakDBListResp (0x0101)

```swift
struct TweakDBListResponse: Codable {
    let records: [TweakDBRecordSummary]
    let totalCount: Int
    let offset: Int
}

struct TweakDBRecordSummary: Codable {
    let id: String               // TweakDBID as string
    let type: String             // Record type
    let flatCount: Int           // Number of flats
    let isModified: Bool         // Modified from base game
}
```

#### TweakDBGet (0x0102)

```swift
struct TweakDBGetRequest: Codable {
    let recordId: String         // TweakDBID
    let includeInherited: Bool   // Include inherited flats
}
```

#### TweakDBGetResp (0x0103)

```swift
struct TweakDBGetResponse: Codable {
    let record: TweakDBRecord?
    let error: String?
}

struct TweakDBRecord: Codable {
    let id: String
    let type: String
    let flats: [TweakDBFlat]
    let baseRecord: String?      // Parent record if cloned
}

struct TweakDBFlat: Codable {
    let name: String
    let type: TweakDBValueType
    let value: TweakDBValue
    let isInherited: Bool
    let isModified: Bool
}

enum TweakDBValueType: String, Codable {
    case int32, int64, float, bool, string
    case cname, tweakDBID, resourcePath
    case array, foreignKey
}

enum TweakDBValue: Codable {
    case int32(Int32)
    case int64(Int64)
    case float(Float)
    case bool(Bool)
    case string(String)
    case cname(String)
    case tweakDBID(String)
    case resourcePath(String)
    case array([TweakDBValue])
    case foreignKey(String)
    case null
}
```

#### TweakDBSet (0x0104)

```swift
struct TweakDBSetRequest: Codable {
    let recordId: String
    let flatName: String
    let value: TweakDBValue
}
```

### 4.3 Hook Messages

#### HookList (0x0200)

```swift
struct HookListRequest: Codable {
    let pluginFilter: String?    // Filter by plugin name
}
```

#### HookListResp (0x0201)

```swift
struct HookListResponse: Codable {
    let hooks: [HookInfo]
}

struct HookInfo: Codable {
    let id: UUID
    let functionName: String
    let addressHash: UInt32
    let resolvedAddress: UInt64
    let pluginName: String
    let hookType: HookType
    let isEnabled: Bool
}

enum HookType: String, Codable {
    case before, after, wrap, replace
}
```

#### HookStats (0x0202)

```swift
struct HookStatsRequest: Codable {
    let hookIds: [UUID]?         // nil = all hooks
    let includeCallHistory: Bool
}
```

#### HookStatsResp (0x0203)

```swift
struct HookStatsResponse: Codable {
    let stats: [HookStatistics]
}

struct HookStatistics: Codable {
    let hookId: UUID
    let callCount: UInt64
    let totalExecutionTimeNs: UInt64
    let avgExecutionTimeNs: UInt64
    let minExecutionTimeNs: UInt64
    let maxExecutionTimeNs: UInt64
    let lastCallTimestamp: Date?
    let recentCalls: [HookCall]? // If includeCallHistory
}

struct HookCall: Codable {
    let timestamp: Date
    let executionTimeNs: UInt64
    let threadId: UInt64
}
```

### 4.4 Memory Messages

#### MemoryRead (0x0400)

```swift
struct MemoryReadRequest: Codable {
    let address: UInt64
    let size: Int
    let format: MemoryFormat?
}

enum MemoryFormat: String, Codable {
    case raw, hex, ascii, struct_
}
```

#### MemoryReadResp (0x0401)

```swift
struct MemoryReadResponse: Codable {
    let address: UInt64
    let data: Data
    let formatted: String?       // If format specified
    let error: String?
}
```

#### MemoryRegions (0x0402)

```swift
struct MemoryRegionsRequest: Codable {
    let includeProtection: Bool
}
```

#### MemoryRegionsResp (0x0403)

```swift
struct MemoryRegionsResponse: Codable {
    let regions: [MemoryRegion]
}

struct MemoryRegion: Codable {
    let baseAddress: UInt64
    let size: UInt64
    let name: String?            // Segment/section name
    let protection: String       // "rwx" format
    let type: RegionType
}

enum RegionType: String, Codable {
    case text, data, heap, stack, mapped, unknown
}
```

### 4.5 Log Messages

#### LogSubscribe (0x0600)

```swift
struct LogSubscribeRequest: Codable {
    let sources: [LogSource]?    // nil = all
    let minLevel: LogLevel?
}

enum LogSource: String, Codable {
    case red4ext, plugin, game, debugAgent
}

enum LogLevel: String, Codable {
    case trace, debug, info, warning, error, critical
}
```

#### LogEntry (0x0602)

```swift
struct LogEntryMessage: Codable {
    let timestamp: Date
    let source: LogSource
    let level: LogLevel
    let message: String
    let metadata: [String: String]?
}
```

### 4.6 Error Message

```swift
struct ErrorMessage: Codable {
    let code: ErrorCode
    let message: String
    let details: String?
    let requestType: UInt16?     // Original request that caused error
}

enum ErrorCode: UInt32, Codable {
    case unknown = 0
    case invalidMessage = 1
    case unsupportedVersion = 2
    case notConnected = 3
    case timeout = 4
    case notFound = 100
    case accessDenied = 101
    case invalidAddress = 102
    case invalidValue = 103
    case operationFailed = 200
}
```

## 5. Connection Lifecycle

```
┌─────────────┐                              ┌─────────────┐
│   Studio    │                              │DebugAgent   │
└──────┬──────┘                              └──────┬──────┘
       │                                            │
       │  ──────── Connect (Unix Socket) ────────▶ │
       │                                            │
       │  ──────── Handshake (0x0001) ───────────▶ │
       │                                            │
       │  ◀─────── HandshakeAck (0x0002) ───────── │
       │                                            │
       │  ══════════ Session Established ══════════│
       │                                            │
       │  ──────── TweakDBList (0x0100) ─────────▶ │
       │  ◀─────── TweakDBListResp (0x0101) ────── │
       │                                            │
       │  ──────── LogSubscribe (0x0600) ────────▶ │
       │  ◀─────── LogEntry (0x0602) ────────────  │
       │  ◀─────── LogEntry (0x0602) ────────────  │
       │                                            │
       │  ──────── Heartbeat (0x0003) ───────────▶ │
       │  ◀─────── Heartbeat (0x0003) ────────────  │
       │                                            │
       │  ──────── Disconnect (0x0004) ──────────▶ │
       │                                            │
       ▼                                            ▼
```

## 6. Swift Implementation

### 6.1 Protocol Client

```swift
// Sources/CyberModCore/IPC/DebugClient.swift
public actor DebugClient {
    private var connection: NWConnection?
    private var messageHandler: ((Message) -> Void)?
    private var pendingRequests: [UInt32: CheckedContinuation<Message, Error>] = [:]
    private var nextRequestId: UInt32 = 1
    
    public func connect(to pid: pid_t) async throws {
        let socketPath = "/tmp/cybermod-debug-\(pid).sock"
        let endpoint = NWEndpoint.unix(path: socketPath)
        
        connection = NWConnection(to: endpoint, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleStateChange(state) }
        }
        connection?.start(queue: .global())
        
        // Wait for connection
        try await waitForConnection()
        
        // Perform handshake
        try await performHandshake()
        
        // Start receive loop
        Task { await receiveLoop() }
    }
    
    public func getTweakDBRecords(
        filter: TweakDBFilter? = nil,
        offset: Int = 0,
        limit: Int = 100
    ) async throws -> TweakDBListResponse {
        let request = TweakDBListRequest(
            filter: filter,
            offset: offset,
            limit: limit
        )
        
        let response = try await sendRequest(
            type: .tweakDBList,
            payload: request
        )
        
        return try decode(response.payload)
    }
    
    public func setTweakDBValue(
        recordId: String,
        flatName: String,
        value: TweakDBValue
    ) async throws {
        let request = TweakDBSetRequest(
            recordId: recordId,
            flatName: flatName,
            value: value
        )
        
        let response = try await sendRequest(
            type: .tweakDBSet,
            payload: request
        )
        
        let result: TweakDBSetResponse = try decode(response.payload)
        if !result.success {
            throw IPCError.operationFailed(result.error ?? "Unknown error")
        }
    }
    
    public func subscribeToLogs(
        sources: [LogSource]? = nil,
        minLevel: LogLevel? = nil,
        handler: @escaping (LogEntryMessage) -> Void
    ) async throws {
        let request = LogSubscribeRequest(
            sources: sources,
            minLevel: minLevel
        )
        
        _ = try await sendRequest(type: .logSubscribe, payload: request)
        
        // Set up log handler
        self.logHandler = handler
    }
    
    private func sendRequest<T: Encodable>(
        type: MessageType,
        payload: T
    ) async throws -> Message {
        let requestId = nextRequestId
        nextRequestId += 1
        
        let payloadData = try encode(payload)
        let message = Message(
            type: type,
            requestId: requestId,
            payload: payloadData
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation
            
            Task {
                do {
                    try await send(message)
                } catch {
                    pendingRequests.removeValue(forKey: requestId)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

### 6.2 Protocol Server (DebugAgent)

```cpp
// DebugAgent/IPCServer.hpp
class IPCServer {
public:
    void start(pid_t gamePid);
    void stop();
    
    // Message handlers
    void onTweakDBList(const TweakDBListRequest& req, ResponseCallback cb);
    void onTweakDBGet(const TweakDBGetRequest& req, ResponseCallback cb);
    void onTweakDBSet(const TweakDBSetRequest& req, ResponseCallback cb);
    void onHookList(const HookListRequest& req, ResponseCallback cb);
    void onMemoryRead(const MemoryReadRequest& req, ResponseCallback cb);
    
private:
    int serverSocket_ = -1;
    std::thread acceptThread_;
    std::vector<std::thread> clientThreads_;
    std::atomic<bool> running_{false};
    
    void acceptLoop();
    void clientLoop(int clientSocket);
    void handleMessage(int clientSocket, const Message& msg);
};
```

## 7. Security Considerations

### 7.1 Socket Permissions

```swift
// Create socket with restricted permissions
let socketPath = "/tmp/cybermod-debug-\(pid).sock"
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
chmod(socketPath, 0600)  // Owner read/write only
```

### 7.2 Process Validation

```swift
// Verify connecting process is CyberMod Studio
func validateClient(pid: pid_t) -> Bool {
    var info = proc_bsdinfo()
    let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    
    guard size > 0 else { return false }
    
    let name = withUnsafePointer(to: info.pbi_name) {
        String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }
    
    return name == "CyberModStudio"
}
```

### 7.3 Message Validation

- All messages validated against schema before processing
- Maximum message size: 16MB
- Rate limiting: 1000 messages/second per client
- Timeout: 30 seconds for requests without response

## 8. Performance Considerations

### 8.1 Batching

For bulk operations, use batch messages:

```swift
struct TweakDBBatchGetRequest: Codable {
    let recordIds: [String]      // Up to 100 records
}

struct TweakDBBatchGetResponse: Codable {
    let records: [String: TweakDBRecord?]
}
```

### 8.2 Streaming

For large data transfers (memory dumps), use chunked streaming:

```swift
struct MemoryReadChunkedRequest: Codable {
    let address: UInt64
    let totalSize: Int
    let chunkSize: Int           // Default 64KB
}

struct MemoryReadChunk: Codable {
    let offset: Int
    let data: Data
    let isLast: Bool
}
```

### 8.3 Caching

Client-side caching for static data:

```swift
actor TweakDBCache {
    private var recordTypes: [String: RecordTypeInfo]?
    private var cacheTime: Date?
    
    func getRecordTypes() async throws -> [String: RecordTypeInfo] {
        if let types = recordTypes,
           let time = cacheTime,
           Date().timeIntervalSince(time) < 300 {  // 5 min cache
            return types
        }
        
        let types = try await client.getRecordTypes()
        self.recordTypes = types
        self.cacheTime = Date()
        return types
    }
}
```
