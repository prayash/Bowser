//
//  Database.swift
//  Bowser
//
//  Created by Prayash Thapa on 3/9/25.
//  Copyright © 2025 prayash.io. All rights reserved.
//

import Foundation
import SQLite3

actor Database {
    var impl: DatabaseImpl
    
    init(url: URL) throws {
        print("sqlite3 \(url.path())")
        self.impl = try DatabaseImpl(url: url)
    }
    
    func setup() throws {
        try self.impl.setup()
    }
    
    func insert(page: Page) throws {
        try impl.execute(
            query: "INSERT INTO PageData (id, title, url, lastUpdated, fullText, snapshot) VALUES (?, ?, ?, ?, ?, ?)",
            params: page.id,
            page.title,
            page.url,
            page.lastUpadated,
            page.fullText,
            page.snapshot
        )
    }
}

final class DatabaseImpl {
    struct DBError: Error {
        let line: UInt
        let code: Int32
        let message: String
    }
    
    var connection: OpaquePointer?
    
    init(url: URL) throws {
        var conn: OpaquePointer?
        try checkError {
            url.absoluteString.withCString { (cStr: UnsafePointer<Int8>) in
                sqlite3_open(cStr, &conn)
            }
        }
        
        self.connection = conn
    }
    
    func setup() throws {
        let query = """
        CREATE TABLE PageData (
            id TEXT PRIMARY KEY NOT NULL,
            lastUpdated INTEGER NOT NULL,
            url TEXT NOT NULL,
            title TEXT NOT NULL,
            fullText TEXT,
            snapshot BLOB
        );
        """
        
        var statement: OpaquePointer?
        try checkError {
            query.withCString { (cStr: UnsafePointer<Int8>) in
                sqlite3_prepare_v3(connection, cStr, -1, 0, &statement, nil)
            }
        }
        
        let returnCode = sqlite3_step(statement)
        guard returnCode == SQLITE_DONE else {
            try checkError { returnCode }
            return
        }
        
        try checkError { sqlite3_finalize(statement) }
    }
    
    func execute(query: String, params: Bindable...) throws {
        var statement: OpaquePointer?
        try checkError {
            query.withCString { (cStr: UnsafePointer<Int8>) in
                sqlite3_prepare_v3(connection, cStr, -1, 0, &statement, nil)
            }
        }
        
        for (parameter, index) in zip(params, (1 as Int32)...) {
            try parameter.bind(statement: statement, column: index)
        }
        
        let returnCode = sqlite3_step(statement)
        guard returnCode == SQLITE_DONE else {
            try checkError { returnCode }
            return
        }
        
        try checkError { sqlite3_finalize(statement) }
    }
}

protocol Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws
}

extension Int64: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        sqlite3_bind_int64(statement, column, self)
    }
}

extension URL: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try absoluteString.bind(statement: statement, column: column)
    }
}

extension UUID: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try uuidString.bind(statement: statement, column: column)
    }
}

extension Date: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try Int64(timeIntervalSince1970).bind(statement: statement, column: column)
    }
}

extension Data: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try checkError {
            withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                sqlite3_bind_blob(statement, column, ptr.baseAddress, Int32(ptr.count), SQLITE_TRANSIENT)
            }
        }
    }
}

extension Optional: Bindable where Wrapped: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        switch self {
        case .none:
            sqlite3_bind_null(statement, column)
        case .some(let wrapped):
            try wrapped.bind(statement: statement, column: column)
        }
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension String: Bindable {
    func bind(statement: OpaquePointer?, column: Int32) throws {
        try checkError {
            self.withCString { (cStr: UnsafePointer<Int8>) in
                sqlite3_bind_text(statement, column, cStr, -1, SQLITE_TRANSIENT)
            }
        }
    }
}

func checkError(line: UInt = #line, _ fn: () -> Int32) throws {
    let returnCode: Int32 = fn()
    guard returnCode == SQLITE_OK else {
        let msg = String(cString: sqlite3_errstr(returnCode))
        throw DatabaseImpl.DBError(line: line, code: returnCode, message: msg)
    }
}

func test() {
    Task {
        do {
            let url = URL.downloadsDirectory.appending(path: "db.sqlite")
            let db = try Database(url: url)
//            try await db.setup()
            try await db.insert(page: .init(url: .init(string: "https://prayash.io")!))
        } catch {
            print("Error", error)
        }
    }
}
