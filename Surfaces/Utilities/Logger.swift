import os

enum Log {
    static let auth = Logger(subsystem: "coops.surfaces", category: "auth")
    static let sync = Logger(subsystem: "coops.surfaces", category: "sync")
    static let desktop = Logger(subsystem: "coops.surfaces", category: "desktop")
}
