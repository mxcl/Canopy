import struct Foundation.ObjCBool
import class Foundation.FileManager
import func Foundation.exit
import PromiseKit

var isDir: ObjCBool = false
precondition(FileManager.default.fileExists(atPath: "../receipts", isDirectory: &isDir) && isDir.boolValue)
precondition(FileManager.default.fileExists(atPath: "../db.sqlite"))

let teamId = "TEQMQBRC7B"

PromiseKit.conf.Q.map = .global()
PromiseKit.conf.Q.return = .global()

import PerfectNotifications

extension NotificationPusher {
    static let sandboxConfigurationName = "com.codebasesaga.sandbox"
    static let productionConfigurationName = "com.codebasesaga.production"
}

NotificationPusher.addConfigurationAPNS(
    name: NotificationPusher.sandboxConfigurationName,
    production: false,
    keyId: "5354D789X6",
    teamId: teamId,
    privateKeyPath: "./AuthKey_5354D789X6.p8")

NotificationPusher.addConfigurationAPNS(
    name: NotificationPusher.productionConfigurationName,
    production: true,
    keyId: "5354D789X6",
    teamId: teamId,
    privateKeyPath: "./AuthKey_5354D789X6.p8")

import PerfectHTTPServer
import PerfectHTTP
import Foundation

private extension Routes {
    mutating func add(method: HTTPMethod, uri: URL.Canopy, handler: @escaping RequestHandler) {
        add(method: method, uri: uri.path, handler: handler)
    }
}

var routes = Routes()
routes.add(method: .post, uri: .grapnel, handler: githubHandler)
routes.add(method: .post, uri: .token, handler: updateTokensHandler)
routes.add(method: .delete, uri: .token, handler: deleteTokenHandler)
routes.add(method: .get, uri: .redirect, handler: oauthCallback)
routes.add(method: .get, uri: .subscribe, handler: subscriptionsHandler)
routes.add(method: .post, uri: .subscribe, handler: subscribeHandler)
routes.add(method: .delete, uri: .subscribe, handler: unsubscribeHandler)
routes.add(method: .post, uri: .receipt, handler: receiptHandler)
routes.add(method: .post, uri: .hook, handler: createHookHandler)
routes.add(method: .get, uri: .hook, handler: hookQueryHandler)

let server = HTTPServer()
server.addRoutes(routes)
#if os(Linux)
    server.runAsUser = "ubuntu"
    server.serverPort = 443
    server.ssl = (
        sslCert: "/etc/letsencrypt/live/canopy.codebasesaga.com/fullchain.pem",
        sslKey: "/etc/letsencrypt/live/canopy.codebasesaga.com/privkey.pem"
    )
#else
    server.serverPort = 1088
#endif


import Dispatch

signal(SIGINT, SIG_IGN) // prevent termination

var running = true
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
sigint.setEventHandler {
    //TODO thread-safety
    if running {
        running = false
        print("Clean shutdown initiated")
        server.stop()
        //FIXME no way to cleanly stop the APNs engine
    } else {
        print("Already shutting down or not yet started")
    }
}
sigint.resume()

try server.start()

print("HTTPServer shutdown")
