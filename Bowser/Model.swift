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
    struct DBError: Error {
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
                sqlite3_prepare_v3(conn, cStr, -1, 0, &statement, nil)
            }
        }
        
        let returnCode = sqlite3_step(statement)
        guard returnCode == SQLITE_DONE else {
            try checkError { returnCode }
            return
        }
        
        try checkError { sqlite3_finalize(statement) }
    }
    
    func setup() throws {
        
    }
}

func checkError(_ fn: () -> Int32) throws {
    let returnCode: Int32 = fn()
    guard returnCode == SQLITE_OK else {
        let msg = String(cString: sqlite3_errstr(returnCode))
        throw Database.DBError(code: returnCode, message: msg)
    }
}
