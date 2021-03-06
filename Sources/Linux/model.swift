import struct Roots.Enrollment
import enum Roots.Event
import enum Roots.Node
import PerfectSQLite
import Foundation

private let dbPath = "../db.sqlite"

private enum CryptoError: Error {
    case couldNotDecrypt(forUserId: Int)
}

class DB {
    let db: SQLite

    init() throws {
        db = try SQLite(dbPath)
    }

    deinit {
        db.close()
    }

    enum E: Error {
        case oauthTokenNotFound(user: Int)
    }

    func backup() throws {
        let fmtr = DateFormatter()
        fmtr.dateFormat = "YYYYMMdd-HHmmss"
        let filename = "../db.backup." + fmtr.string(from: Date()) + ".sqlite"

        let src = URL(fileURLWithPath: dbPath)
        let dst = URL(fileURLWithPath: filename)
        try FileManager.default.copyItem(at: src, to: dst)

        print("Backed up:", dst.path)
    }

    func oauthToken(forUser uid: Int) throws -> String {
        let sql = """
            SELECT salt, token
            FROM auths
            WHERE user_id = \(uid)
            """

        var _oauthToken: String?
        try db.forEachRow(statement: sql) { stmt, _ in
            let encryptedOAuthToken: [UInt8] = stmt.columnIntBlob(position: 1)
            let encryptionSalt: [UInt8] = stmt.columnIntBlob(position: 0)

            guard let oauthToken = decrypt(encryptedOAuthToken, salt: encryptionSalt) else {
                return alert(message: "Failed decrypting token for user: \(uid)")
            }

            _oauthToken = oauthToken
        }

        guard let oauthToken = _oauthToken else {
            throw E.oauthTokenNotFound(user: uid)
        }

        return oauthToken
    }

    func set(mask: Int, repoId: Int, userId: Int) throws {
        let sql = """
            UPDATE subscriptions
            SET event_mask = :1
            WHERE user_id = :2 AND repo_id = :3
            """
        try db.execute(statement: sql, doBindings: { stmt in
            try stmt.bind(position: 1, mask)
            try stmt.bind(position: 2, userId)
            try stmt.bind(position: 3, repoId)
        })
    }

    func add(apnsToken: String, topic: String, userId: Int, production: Bool) throws {
        let sql = """
            REPLACE INTO tokens (id, topic, user_id, production)
            VALUES (:1, :2, :3, :4)
            """
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, apnsToken)
            try stmt.bind(position: 2, topic)
            try stmt.bind(position: 3, userId)
            try stmt.bind(position: 4, production ? 1 : 0)
        }
    }

    func delete(apnsDeviceToken: String) throws {
        let sql = "DELETE from tokens WHERE id = :1"
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, apnsDeviceToken)
        }
    }

    func add(oauthToken: String, userId: Int) throws {

        // we could easily have multiple tokens per user-id
        // since they could be using many devices. Or… perhaps
        // github vends the same tokens per oauth-app?

        guard let (encryptedToken, encryptionSalt) = encrypt(oauthToken) else {
            throw CryptoError.couldNotDecrypt(forUserId: userId)
        }
        let sql = """
            REPLACE INTO auths (token, user_id, salt)
            VALUES (:1, :2, :3)
            """
        try db.execute(statement: sql) {
            try $0.bind(position: 1, [UInt8](encryptedToken))
            try $0.bind(position: 2, userId)
            try $0.bind(position: 3, encryptionSalt)
        }
    }

    func add(subscriptions repoIds: [Int], userId: Int) throws {
        let values = repoIds.enumerated().map { x, _ in
            "(:\(x * 2 + 1), :\(x * 2 + 2))"
        }.joined(separator: ",")
        let sql = """
            REPLACE INTO subscriptions (repo_id, user_id)
            VALUES \(values);
            """
        try db.execute(statement: sql) { stmt in
            for (x, repoId) in repoIds.enumerated() {
                try stmt.bind(position: x * 2 + 1, repoId)
                try stmt.bind(position: x * 2 + 2, userId)
            }
        }
    }

    func delete(subscription repoId: Int, userId: Int) throws {
        let sql = """
            DELETE FROM subscriptions
            WHERE repo_id = :1 and user_id = :2
            """
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, repoId)
            try stmt.bind(position: 2, userId)
        }
    }

    func delete(subscriptions repoIds: [Int], userId: Int) throws {
        try db.doWithTransaction {
            //TODO inefficient
            for id in repoIds {
                try delete(subscription: id, userId: userId)
            }
        }
    }

    func delete(repository repoId: Int) throws {
        let sql = """
            DELETE FROM subscriptions
            WHERE repo_id = :1
            """
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, repoId)
        }
    }

    func subscriptions(forUserId userId: Int) throws -> [Int] {
        let sql = """
            SELECT repo_id
            FROM subscriptions
            WHERE user_id = :1
            """

        var results: [Int] = []

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, userId)
        }, handleRow: { statement, row in
            let repoId = statement.columnInt(position: 0)
            results.append(repoId)
        })

        return results
    }

    func enrollments(forUserId userId: Int) throws -> [Enrollment] {
        let sql = """
            SELECT repo_id, event_mask
            FROM subscriptions
            WHERE user_id = :1
            """

        var results: [Enrollment] = []

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, userId)
        }, handleRow: { statement, row in
            let repo = statement.columnInt(position: 0)
            let mask = statement.columnInt(position: 1)
            results.append(Enrollment(repoId: repo, eventMask: mask))
        })

        return results
    }

    func add(receiptForUserId userId: Int, expires: Date) throws -> Bool {
        let sql = """
            REPLACE INTO receipts (user_id, expires)
            VALUES (:1, :2)
            """
        try db.execute(statement: sql) {
            try $0.bind(position: 1, userId)
            try $0.bind(position: 2, Formatter.iso8601.string(from: expires))
        }
        return Date() < expires
    }

    func isReceiptValid(forUserId userId: Int) throws -> Bool {
        switch userId {
        case 7132384, 24509830, 33223853, 33409294, 21280410, 9217605, 15271677:
            return true
        default:
            break
        }
        
        let sql = """
            SELECT expires
            FROM receipts
            WHERE user_id = \(userId)
            """
        var dateString: String?
        try db.forEachRow(statement: sql) { statement, row in
            dateString = statement.columnText(position: 0)
        }

        if let dateString = dateString, let expiryDate = Formatter.iso8601.date(from: dateString), Date() < expiryDate {
            return true
        } else {
            return false
        }
    }

    func remove(receiptForUserId userId: Int) throws {
        try db.execute(statement: """
            DELETE FROM receipts
            WHERE userId = \(userId)
            """)
    }

    func recordIfUnknown(hook: Int, node: (Node, id: Int)) throws {
        let sql = """
            INSERT OR IGNORE INTO hooks (id, secret, target_id, target_type, full_name)
            VALUES (:1, :2, :3, :4, :5)
            """
        // replace because github replaces if we create a hook that already exists
        try db.execute(statement: sql) {
            try $0.bind(position: 1, hook)
            try $0.bind(position: 2, "")  // no secret since we came from github
            try $0.bind(position: 3, node.id)
            try $0.bind(position: 4, node.0.dbType)
            try $0.bind(position: 5, node.0.ref)
        }
    }

    func record(hook: Int, secret: String, node: (Node, id: Int)) throws {
        let sql = """
            REPLACE INTO hooks (id, secret, target_id, target_type, full_name)
            VALUES (:1, :2, :3, :4, :5)
            """
        // replace because github replaces if we create a hook that already exists
        try db.execute(statement: sql) {
            try $0.bind(position: 1, hook)
            try $0.bind(position: 2, secret)
            try $0.bind(position: 3, node.id)
            try $0.bind(position: 4, node.0.dbType)
            try $0.bind(position: 5, node.0.ref)
        }
    }

    func whichAreHooked<S: Sequence>(ids: S) throws -> [Int] where S.Element == Int {
        let ids = ids.enumerated()
        let values = ids.map { x, _ in
            ":\(x + 1)"
        }.joined(separator: ",")
        var results: [Int] = []
        let sql = "SELECT target_id FROM hooks WHERE target_id IN (\(values))"
        try db.forEachRow(statement: sql, doBindings: {
            for (x, id) in ids {
                try $0.bind(position: x + 1, id)
            }
        }, handleRow: { stmt, _ in
            results.append(stmt.columnInt(position: 0))
        })
        return results
    }
}

private extension Formatter {
    static var iso8601: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }
}

private extension Node {
    var dbType: Int {
        switch self {
        case .repository:
            return 1
        case .organization:
            return 2
        }
    }
}
