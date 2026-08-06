//
//  Log.swift
//  ReclaimKit
//
//  Centralized os.log categories so log output stays consistent and
//  filterable in Console.app (subsystem: com.allwiine.reclaim).
//

import os

/// Namespaced loggers for each subsystem area.
public enum Log {
    private static let subsystem = "com.allwiine.reclaim"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let scanner = Logger(subsystem: subsystem, category: "scanner")
    public static let cleaner = Logger(subsystem: subsystem, category: "cleaner")
}
