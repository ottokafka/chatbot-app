import Foundation
import FSRS
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
    let audioPath: String?
    /// Original STT text when content was corrected for learner speech.
    let rawContent: String?
    /// Short pronunciation / phrasing note from the correction layer.
    let tutorFeedback: String?
    let createdAt: Date

    init(
        id: String,
        conversationId: String,
        role: String,
        content: String,
        audioPath: String? = nil,
        rawContent: String? = nil,
        tutorFeedback: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.audioPath = audioPath
        self.rawContent = rawContent
        self.tutorFeedback = tutorFeedback
        self.createdAt = createdAt
    }
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

    init(databasePath: String? = nil) {
        if let databasePath {
            self.dbPath = databasePath
        } else {
            let fileManager = FileManager.default
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirURL = appSupportURL.appendingPathComponent("DeveloperChatbot")

            do {
                try fileManager.createDirectory(at: appDirURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("DatabaseManager: Failed to create app directory: \(error)")
            }

            self.dbPath = appDirURL.appendingPathComponent("history.sqlite").path
        }
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
        
        let createFlashcardsTable = """
        CREATE TABLE IF NOT EXISTS flashcards (
            id TEXT PRIMARY KEY,
            front TEXT NOT NULL,
            back TEXT NOT NULL,
            phonics TEXT,
            source_message_id TEXT,
            source_conversation_id TEXT,
            created_at REAL NOT NULL,
            due REAL NOT NULL,
            stability REAL NOT NULL,
            difficulty REAL NOT NULL,
            elapsed_days REAL NOT NULL DEFAULT 0,
            scheduled_days REAL NOT NULL DEFAULT 0,
            learning_steps INTEGER NOT NULL DEFAULT 0,
            reps INTEGER NOT NULL DEFAULT 0,
            lapses INTEGER NOT NULL DEFAULT 0,
            state INTEGER NOT NULL DEFAULT 0,
            last_review REAL,
            kind TEXT NOT NULL DEFAULT 'vocab',
            parent_flashcard_id TEXT
        );
        """

        let createFlashcardsDueIndex = """
        CREATE INDEX IF NOT EXISTS idx_flashcards_due ON flashcards(due);
        """

        let createFlashcardsKindDueIndex = """
        CREATE INDEX IF NOT EXISTS idx_flashcards_kind_due ON flashcards(kind, due);
        """

        let createFlashcardsParentIndex = """
        CREATE INDEX IF NOT EXISTS idx_flashcards_parent ON flashcards(parent_flashcard_id);
        """

        let createFlashcardsFrontIndex = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_flashcards_front ON flashcards(front);
        """

        execute(sql: createConversationsTable)
        execute(sql: createMessagesTable)
        execute(sql: createSystemPromptsTable)
        execute(sql: createEndpointsTable)
        execute(sql: createFlashcardsTable)
        execute(sql: createFlashcardsDueIndex)
        execute(sql: createFlashcardsKindDueIndex)
        execute(sql: createFlashcardsParentIndex)
        execute(sql: createFlashcardsFrontIndex)
        migrateDatabase()

        prepopulateDefaultPrompts()
        prepopulateDefaultEndpoints()
    }

    private func migrateDatabase() {
        if !columnExists(table: "messages", column: "audio_path") {
            execute(sql: "ALTER TABLE messages ADD COLUMN audio_path TEXT;")
        }
        if !columnExists(table: "messages", column: "raw_content") {
            execute(sql: "ALTER TABLE messages ADD COLUMN raw_content TEXT;")
        }
        if !columnExists(table: "messages", column: "tutor_feedback") {
            execute(sql: "ALTER TABLE messages ADD COLUMN tutor_feedback TEXT;")
        }
        if columnExists(table: "flashcards", column: "notes") && !columnExists(table: "flashcards", column: "phonics") {
            execute(sql: "ALTER TABLE flashcards RENAME COLUMN notes TO phonics;")
        }
        if !columnExists(table: "flashcards", column: "kind") {
            execute(sql: "ALTER TABLE flashcards ADD COLUMN kind TEXT NOT NULL DEFAULT 'vocab';")
        }
        if !columnExists(table: "flashcards", column: "parent_flashcard_id") {
            execute(sql: "ALTER TABLE flashcards ADD COLUMN parent_flashcard_id TEXT;")
        }
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_flashcards_kind_due ON flashcards(kind, due);")
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_flashcards_parent ON flashcards(parent_flashcard_id);")
    }

    private func columnExists(table: String, column: String) -> Bool {
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        var exists = false

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let nameCol = sqlite3_column_text(statement, 1) {
                    let name = String(cString: nameCol)
                    if name == column {
                        exists = true
                        break
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        return exists
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
        let sql = """
        SELECT id, conversation_id, role, content, audio_path, raw_content, tutor_feedback, created_at
        FROM messages WHERE conversation_id = ? ORDER BY created_at ASC;
        """
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
                    let audioPath = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                    let rawContent = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                    let tutorFeedback = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                    let createdAtVal = sqlite3_column_double(statement, 7)
                    
                    messages.append(Message(
                        id: id,
                        conversationId: convId,
                        role: role,
                        content: content,
                        audioPath: audioPath,
                        rawContent: rawContent,
                        tutorFeedback: tutorFeedback,
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

    func insertMessage(
        id: String = UUID().uuidString,
        conversationId: String,
        role: String,
        content: String,
        rawContent: String? = nil,
        tutorFeedback: String? = nil
    ) {
        let sql = """
        INSERT INTO messages (id, conversation_id, role, content, raw_content, tutor_feedback, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        let now = Date().timeIntervalSince1970
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (conversationId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (role as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (content as NSString).utf8String, -1, nil)
            if let rawContent {
                sqlite3_bind_text(statement, 5, (rawContent as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            if let tutorFeedback {
                sqlite3_bind_text(statement, 6, (tutorFeedback as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_double(statement, 7, now)
            
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

    func updateMessageAudioPath(id: String, audioPath: String) {
        let sql = "UPDATE messages SET audio_path = ? WHERE id = ?;"
        execute(sql: sql, parameters: [audioPath, id])
    }

    func fetchMessageAudioPaths(conversationId: String) -> [String] {
        var paths: [String] = []
        let sql = "SELECT audio_path FROM messages WHERE conversation_id = ? AND audio_path IS NOT NULL;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (conversationId as NSString).utf8String, -1, nil)

            while sqlite3_step(statement) == SQLITE_ROW {
                if let pathCol = sqlite3_column_text(statement, 0) {
                    paths.append(String(cString: pathCol))
                }
            }
        }
        sqlite3_finalize(statement)
        return paths
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

    // MARK: - Flashcards CRUD

    private static let flashcardSelectColumns = """
        id, front, back, phonics, source_message_id, source_conversation_id, created_at,
        due, stability, difficulty, elapsed_days, scheduled_days, learning_steps, reps, lapses, state, last_review,
        kind, parent_flashcard_id
        """

    func fetchFlashcards(kind: FlashcardKind? = nil) -> [Flashcard] {
        var flashcards: [Flashcard] = []
        let sql: String
        if kind != nil {
            sql = """
            SELECT \(Self.flashcardSelectColumns)
            FROM flashcards
            WHERE kind = ?
            ORDER BY due ASC;
            """
        } else {
            sql = """
            SELECT \(Self.flashcardSelectColumns)
            FROM flashcards
            ORDER BY due ASC;
            """
        }
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if let kind {
                sqlite3_bind_text(statement, 1, (kind.rawValue as NSString).utf8String, -1, nil)
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                if let flashcard = parseFlashcard(from: statement) {
                    flashcards.append(flashcard)
                }
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare fetchFlashcards statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return flashcards
    }

    func fetchDueFlashcards(kind: FlashcardKind? = nil, before date: Date = Date()) -> [Flashcard] {
        var flashcards: [Flashcard] = []
        let sql: String
        if kind != nil {
            sql = """
            SELECT \(Self.flashcardSelectColumns)
            FROM flashcards
            WHERE due <= ? AND kind = ?
            ORDER BY due ASC;
            """
        } else {
            sql = """
            SELECT \(Self.flashcardSelectColumns)
            FROM flashcards
            WHERE due <= ?
            ORDER BY due ASC;
            """
        }
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            if let kind {
                sqlite3_bind_text(statement, 2, (kind.rawValue as NSString).utf8String, -1, nil)
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let flashcard = parseFlashcard(from: statement) {
                    flashcards.append(flashcard)
                }
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare fetchDueFlashcards statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return flashcards
    }

    @discardableResult
    func insertFlashcard(_ flashcard: Flashcard) -> String? {
        let sql = """
        INSERT INTO flashcards (
            id, front, back, phonics, source_message_id, source_conversation_id, created_at,
            due, stability, difficulty, elapsed_days, scheduled_days, learning_steps, reps, lapses, state, last_review,
            kind, parent_flashcard_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            bindFlashcard(flashcard, to: statement)

            if sqlite3_step(statement) == SQLITE_DONE {
                sqlite3_finalize(statement)
                return flashcard.id
            }

            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to insert flashcard: \(errmsg)")
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare insert flashcard statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
        return nil
    }

    func updateFlashcardFSRSState(id: String, card: Card) {
        let sql = """
        UPDATE flashcards
        SET due = ?, stability = ?, difficulty = ?, elapsed_days = ?, scheduled_days = ?,
            learning_steps = ?, reps = ?, lapses = ?, state = ?, last_review = ?
        WHERE id = ?;
        """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, card.due.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, card.stability)
            sqlite3_bind_double(statement, 3, card.difficulty)
            sqlite3_bind_double(statement, 4, card.elapsedDays)
            sqlite3_bind_double(statement, 5, card.scheduledDays)
            sqlite3_bind_int(statement, 6, Int32(card.learningSteps))
            sqlite3_bind_int(statement, 7, Int32(card.reps))
            sqlite3_bind_int(statement, 8, Int32(card.lapses))
            sqlite3_bind_int(statement, 9, Int32(card.state.rawValue))
            if let lastReview = card.lastReview {
                sqlite3_bind_double(statement, 10, lastReview.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            sqlite3_bind_text(statement, 11, (id as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to update flashcard FSRS state: \(errmsg)")
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare update flashcard FSRS state statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
    }

    func updateFlashcardContent(id: String, front: String, back: String, phonics: String?) {
        let sql = "UPDATE flashcards SET front = ?, back = ?, phonics = ? WHERE id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (front as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (back as NSString).utf8String, -1, nil)
            if let phonics {
                sqlite3_bind_text(statement, 3, (phonics as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_text(statement, 4, (id as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) != SQLITE_DONE {
                let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
                print("DatabaseManager: Failed to update flashcard content: \(errmsg)")
            }
        } else {
            let errmsg = sqlite3_errmsg(db) != nil ? String(cString: sqlite3_errmsg(db)!) : "Unknown error"
            print("DatabaseManager: Failed to prepare update flashcard content statement: \(errmsg)")
        }
        sqlite3_finalize(statement)
    }

    func deleteFlashcard(id: String) {
        // Keep example cards; clear parent link when a vocab card is removed.
        execute(sql: "UPDATE flashcards SET parent_flashcard_id = NULL WHERE parent_flashcard_id = ?;", parameters: [id])
        execute(sql: "DELETE FROM flashcards WHERE id = ?;", parameters: [id])
    }

    func flashcardExists(front: String, excludingId: String? = nil) -> Bool {
        let sql: String
        if excludingId != nil {
            sql = "SELECT COUNT(*) FROM flashcards WHERE front = ? AND id != ?;"
        } else {
            sql = "SELECT COUNT(*) FROM flashcards WHERE front = ?;"
        }
        var statement: OpaquePointer?
        var exists = false

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (front as NSString).utf8String, -1, nil)
            if let excludingId {
                sqlite3_bind_text(statement, 2, (excludingId as NSString).utf8String, -1, nil)
            }
            if sqlite3_step(statement) == SQLITE_ROW {
                exists = sqlite3_column_int(statement, 0) > 0
            }
        }
        sqlite3_finalize(statement)
        return exists
    }

    private func parseFlashcard(from statement: OpaquePointer?) -> Flashcard? {
        guard let statement,
              let idCol = sqlite3_column_text(statement, 0),
              let frontCol = sqlite3_column_text(statement, 1),
              let backCol = sqlite3_column_text(statement, 2) else {
            return nil
        }

        let id = String(cString: idCol)
        let front = String(cString: frontCol)
        let back = String(cString: backCol)
        let phonics = sqlite3_column_text(statement, 3).map { String(cString: $0) }
        let sourceMessageId = sqlite3_column_text(statement, 4).map { String(cString: $0) }
        let sourceConversationId = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))

        let fsrsCard = Card.fromDatabase(
            due: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
            stability: sqlite3_column_double(statement, 8),
            difficulty: sqlite3_column_double(statement, 9),
            elapsedDays: sqlite3_column_double(statement, 10),
            scheduledDays: sqlite3_column_double(statement, 11),
            learningSteps: Int(sqlite3_column_int(statement, 12)),
            reps: Int(sqlite3_column_int(statement, 13)),
            lapses: Int(sqlite3_column_int(statement, 14)),
            state: CardState(rawValue: Int(sqlite3_column_int(statement, 15))) ?? .new,
            lastReview: sqlite3_column_type(statement, 16) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 16))
        )

        let kindRaw = sqlite3_column_text(statement, 17).map { String(cString: $0) } ?? FlashcardKind.vocab.rawValue
        let kind = FlashcardKind(rawValue: kindRaw) ?? .vocab
        let parentFlashcardId = sqlite3_column_text(statement, 18).map { String(cString: $0) }

        return Flashcard(
            id: id,
            front: front,
            back: back,
            phonics: phonics,
            sourceMessageId: sourceMessageId,
            sourceConversationId: sourceConversationId,
            kind: kind,
            parentFlashcardId: parentFlashcardId,
            createdAt: createdAt,
            fsrsCard: fsrsCard
        )
    }

    private func bindFlashcard(_ flashcard: Flashcard, to statement: OpaquePointer?) {
        guard let statement else { return }

        let card = flashcard.fsrsCard
        sqlite3_bind_text(statement, 1, (flashcard.id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (flashcard.front as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (flashcard.back as NSString).utf8String, -1, nil)
        if let phonics = flashcard.phonics {
            sqlite3_bind_text(statement, 4, (phonics as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        if let sourceMessageId = flashcard.sourceMessageId {
            sqlite3_bind_text(statement, 5, (sourceMessageId as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        if let sourceConversationId = flashcard.sourceConversationId {
            sqlite3_bind_text(statement, 6, (sourceConversationId as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        sqlite3_bind_double(statement, 7, flashcard.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 8, card.due.timeIntervalSince1970)
        sqlite3_bind_double(statement, 9, card.stability)
        sqlite3_bind_double(statement, 10, card.difficulty)
        sqlite3_bind_double(statement, 11, card.elapsedDays)
        sqlite3_bind_double(statement, 12, card.scheduledDays)
        sqlite3_bind_int(statement, 13, Int32(card.learningSteps))
        sqlite3_bind_int(statement, 14, Int32(card.reps))
        sqlite3_bind_int(statement, 15, Int32(card.lapses))
        sqlite3_bind_int(statement, 16, Int32(card.state.rawValue))
        if let lastReview = card.lastReview {
            sqlite3_bind_double(statement, 17, lastReview.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 17)
        }
        sqlite3_bind_text(statement, 18, (flashcard.kind.rawValue as NSString).utf8String, -1, nil)
        if let parentFlashcardId = flashcard.parentFlashcardId {
            sqlite3_bind_text(statement, 19, (parentFlashcardId as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 19)
        }
    }
}
