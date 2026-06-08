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
        
        execute(sql: createConversationsTable)
        execute(sql: createMessagesTable)
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
}
