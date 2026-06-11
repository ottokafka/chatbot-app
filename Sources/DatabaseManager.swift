import Foundation
import SQLite3

struct Conversation: Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    let createdAt: Date
}

struct Message: Identifiable, Equatable, Hashable {
    let id: String
    let conversationId: String
    let role: String
    let content: String
    let createdAt: Date
}

struct SystemPrompt: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let promptText: String
    var isActive: Bool
    let createdAt: Date
}

struct EndpointConfig: Identifiable, Equatable, Hashable {
    let id: Int64
    var name: String
    var isActive: Bool
    var textGenURL: String
    var ttsURL: String
    var sttURL: String
    let createdAt: Date
}

class DatabaseManager {
    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        // Find Application Support Directory
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirURL = appSupportURL.appendingPathComponent("DeveloperChatbot")
        
        do {
            try fileManager.createDirectory(at: appDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("DatabaseManager: Failed to create app directory: \(error)")
        }
        
        self.dbPath = appDirURL.appendingPathComponent("history.sqlite").path
        print("DatabaseManager: Opening database at \(dbPath)")
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let errorMsg = db != nil && sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Error opening database: \(errorMsg)")
        } else {
            // Enable foreign keys
            sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
            createTables()
        }
    }

    deinit {
        sqlite3_close(db)
    }

    private func createTables() {
        let createConversationsTable = """
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """
        
        let createMessagesTable = """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
        );
        """
        
        let createSystemPromptsTable = """
        CREATE TABLE IF NOT EXISTS system_prompts (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            prompt_text TEXT NOT NULL,
            is_active INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
        """
        
        let createEndpointsTable = """
        CREATE TABLE IF NOT EXISTS endpoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            is_active BOOLEAN DEFAULT 0,
            text_gen_url TEXT,
            tts_url TEXT,
            stt_url TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        
        execute(sql: createConversationsTable)
        execute(sql: createMessagesTable)
        execute(sql: createSystemPromptsTable)
        execute(sql: createEndpointsTable)
        
        prepopulateDefaultPrompts()
        prepopulateDefaultEndpoints()
    }

    private func execute(sql: String, parameters: [String] = []) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            for (index, param) in parameters.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), (param as NSString).utf8String, -1, nil)
            }
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to execute statement: \(errmsg)")
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Conversations CRUD

    func fetchConversations() -> [Conversation] {
        var conversations: [Conversation] = []
        let sql = "SELECT id, title, created_at FROM conversations ORDER BY created_at DESC;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let idCol = sqlite3_column_text(statement, 0),
                   let titleCol = sqlite3_column_text(statement, 1) {
                    let id = String(cString: idCol)
                    let title = String(cString: titleCol)
                    let createdAtVal = sqlite3_column_double(statement, 2)
                    
                    conversations.append(Conversation(
                        id: id,
                        title: title,
                        createdAt: Date(timeIntervalSince1970: createdAtVal)
                    ))
                }
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare fetchConversations statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return conversations
    }

    func createConversation(id: String = UUID().uuidString, title: String) -> String {
        let sql = "INSERT INTO conversations (id, title, created_at) VALUES (?, ?, ?);"
        let now = Date().timeIntervalSince1970
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 3, now)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to insert conversation: \(errmsg)")
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare insert conversation statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return id
    }

    func updateConversationTitle(id: String, title: String) {
        let sql = "UPDATE conversations SET title = ? WHERE id = ?;"
        execute(sql: sql, parameters: [title, id])
    }

    func deleteConversation(id: String) {
        let sql = "DELETE FROM conversations WHERE id = ?;"
        execute(sql: sql, parameters: [id])
    }

    // MARK: - Messages CRUD

    func fetchMessages(conversationId: String) -> [Message] {
        var messages: [Message] = []
        let sql = "SELECT id, conversation_id, role, content, created_at FROM messages WHERE conversation_id = ? ORDER BY created_at ASC;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (conversationId as NSString).utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let idCol = sqlite3_column_text(statement, 0),
                   let convIdCol = sqlite3_column_text(statement, 1),
                   let roleCol = sqlite3_column_text(statement, 2),
                   let contentCol = sqlite3_column_text(statement, 3) {
                    
                    let id = String(cString: idCol)
                    let convId = String(cString: convIdCol)
                    let role = String(cString: roleCol)
                    let content = String(cString: contentCol)
                    let createdAtVal = sqlite3_column_double(statement, 4)
                    
                    messages.append(Message(
                        id: id,
                        conversationId: convId,
                        role: role,
                        content: content,
                        createdAt: Date(timeIntervalSince1970: createdAtVal)
                    ))
                }
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare fetchMessages statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return messages
    }

    func insertMessage(id: String = UUID().uuidString, conversationId: String, role: String, content: String) {
        let sql = "INSERT INTO messages (id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?);"
        let now = Date().timeIntervalSince1970
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (conversationId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (role as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 5, now)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to insert message: \(errmsg)")
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare insert message: \(errmsg)")
        }
        sqlite3_finalize(statement)
    }
    
    private func prepopulateDefaultPrompts() {
        let sql = "SELECT COUNT(*) FROM system_prompts;"
        var statement: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        if count == 0 {
            print("DatabaseManager: Pre-populating default system prompts...")
            let p1Id = UUID().uuidString
            let p1Title = "Chinese Teacher"
            let p1Text = "You are an expert Chinese language teacher, fluent in both Mandarin and English, with deep knowledge of Chinese culture, history, and linguistics. Your goal is to help users learn Chinese effectively, accurately, and politely. respond with 2 sentences maximum."
            
            let p2Id = UUID().uuidString
            let p2Title = "Casual Conversation"
            let p2Text = "You are a friendly Chinese conversational partner. Engage in casual, natural conversations with the user in Chinese, keeping your responses short, warm, and appropriate for daily-life scenarios. Explain things in English if requested. respond with 2 sentences maximum."
            
            insertSystemPrompt(id: p1Id, title: p1Title, promptText: p1Text, isActive: true)
            insertSystemPrompt(id: p2Id, title: p2Title, promptText: p2Text, isActive: false)
        }
    }
    
    private func insertSystemPrompt(id: String, title: String, promptText: String, isActive: Bool) {
        let sql = "INSERT INTO system_prompts (id, title, prompt_text, is_active, created_at) VALUES (?, ?, ?, ?, ?);"
        let now = Date().timeIntervalSince1970
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (promptText as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 4, isActive ? 1 : 0)
            sqlite3_bind_double(statement, 5, now)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("DatabaseManager: Failed to insert system prompt: \(title)")
            }
        }
        sqlite3_finalize(statement)
    }
    
    // MARK: - System Prompts CRUD
    
    func fetchSystemPrompts() -> [SystemPrompt] {
        var prompts: [SystemPrompt] = []
        let sql = "SELECT id, title, prompt_text, is_active, created_at FROM system_prompts ORDER BY created_at ASC;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let idCol = sqlite3_column_text(statement, 0),
                   let titleCol = sqlite3_column_text(statement, 1),
                   let textCol = sqlite3_column_text(statement, 2) {
                    
                    let id = String(cString: idCol)
                    let title = String(cString: titleCol)
                    let text = String(cString: textCol)
                    let activeVal = sqlite3_column_int(statement, 3)
                    let createdAtVal = sqlite3_column_double(statement, 4)
                    
                    prompts.append(SystemPrompt(
                        id: id,
                        title: title,
                        promptText: text,
                        isActive: activeVal == 1,
                        createdAt: Date(timeIntervalSince1970: createdAtVal)
                    ))
                }
            }
        }
        sqlite3_finalize(statement)
        return prompts
    }
    
    func createSystemPrompt(id: String = UUID().uuidString, title: String, promptText: String) -> String {
        insertSystemPrompt(id: id, title: title, promptText: promptText, isActive: false)
        return id
    }
    
    func setActiveSystemPrompt(id: String) {
        let sqlDeactivate = "UPDATE system_prompts SET is_active = 0;"
        execute(sql: sqlDeactivate)
        
        let sqlActivate = "UPDATE system_prompts SET is_active = 1 WHERE id = ?;"
        execute(sql: sqlActivate, parameters: [id])
    }
    
    func updateSystemPrompt(id: String, title: String, promptText: String) {
        let sql = "UPDATE system_prompts SET title = ?, prompt_text = ? WHERE id = ?;"
        execute(sql: sql, parameters: [title, promptText, id])
    }
    
    func deleteSystemPrompt(id: String) {
        let sql = "DELETE FROM system_prompts WHERE id = ?;"
        execute(sql: sql, parameters: [id])
    }
    
    // MARK: - Endpoints CRUD
    
    private func prepopulateDefaultEndpoints() {
        let sql = "SELECT COUNT(*) FROM endpoints;"
        var statement: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        if count == 0 {
            print("DatabaseManager: Pre-populating default endpoint configurations...")
            let defaults = UserDefaults.standard
            let stt = defaults.string(forKey: "sttURL") ?? "wss://speech_to_text.npro.ai?silence_duration_ms=1000"
            let llm = defaults.string(forKey: "llmURL") ?? "https://text_gen.npro.ai/v1/chat/completions"
            let tts = defaults.string(forKey: "ttsURL") ?? "https://text_to_speech.npro.ai/v1/audio/speech"
            
            _ = createEndpoint(name: "Default Config", textGenURL: llm, ttsURL: tts, sttURL: stt, isActive: true)
        }
    }
    
    func fetchEndpoints() -> [EndpointConfig] {
        var configs: [EndpointConfig] = []
        let sql = "SELECT id, name, is_active, text_gen_url, tts_url, stt_url, created_at FROM endpoints ORDER BY created_at ASC;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                
                guard let nameCol = sqlite3_column_text(statement, 1) else { continue }
                let name = String(cString: nameCol)
                
                let isActiveVal = sqlite3_column_int(statement, 2)
                
                let textGenURL = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let ttsURL = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let sttURL = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                
                var createdAt = Date()
                if let dateCol = sqlite3_column_text(statement, 6) {
                    let dateStr = String(cString: dateCol)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    if let date = formatter.date(from: dateStr) {
                        createdAt = date
                    } else {
                        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                        if let date = formatter.date(from: dateStr) {
                            createdAt = date
                        }
                    }
                }
                
                configs.append(EndpointConfig(
                    id: id,
                    name: name,
                    isActive: isActiveVal != 0,
                    textGenURL: textGenURL,
                    ttsURL: ttsURL,
                    sttURL: sttURL,
                    createdAt: createdAt
                ))
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare fetchEndpoints statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return configs
    }
    
    func createEndpoint(name: String, textGenURL: String, ttsURL: String, sttURL: String, isActive: Bool = false) -> Int64 {
        let sql = "INSERT INTO endpoints (name, is_active, text_gen_url, tts_url, stt_url) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        var newId: Int64 = -1
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, isActive ? 1 : 0)
            sqlite3_bind_text(statement, 3, (textGenURL as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (ttsURL as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (sttURL as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                newId = sqlite3_last_insert_rowid(db)
            } else {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to insert endpoint: \(errmsg)")
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare insert endpoint statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return newId
    }
    
    func updateEndpoint(id: Int64, name: String, textGenURL: String, ttsURL: String, sttURL: String) {
        let sql = "UPDATE endpoints SET name = ?, text_gen_url = ?, tts_url = ?, stt_url = ? WHERE id = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (textGenURL as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (ttsURL as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (sttURL as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 5, id)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to update endpoint: \(errmsg)")
            }
        }
        sqlite3_finalize(statement)
    }
    
    func deleteEndpoint(id: Int64) {
        let sql = "DELETE FROM endpoints WHERE id = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, id)
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to delete endpoint: \(errmsg)")
            }
        }
        sqlite3_finalize(statement)
    }
    
    func setActiveEndpoint(id: Int64) {
        let deactivateSql = "UPDATE endpoints SET is_active = 0;"
        execute(sql: deactivateSql)
        
        let activateSql = "UPDATE endpoints SET is_active = 1 WHERE id = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, activateSql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, id)
            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to set active endpoint: \(errmsg)")
            }
        }
        sqlite3_finalize(statement)
    }
}
