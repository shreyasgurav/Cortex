//
//  EnvironmentLoader.swift
//  Cortex
//
//  Loads .env file into process environment
//

import Foundation

/// Loads environment variables from .env file
enum EnvironmentLoader {
    /// Load .env file from project root
    static func load() {
        guard let envPath = findEnvFile() else {
            print("[EnvironmentLoader] No .env file found")
            return
        }
        
        guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            print("[EnvironmentLoader] Failed to read .env file")
            return
        }
        
        var loaded = 0
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Parse KEY=VALUE
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                
                // Remove quotes if present
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || 
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                
                // Set environment variable
                setenv(key, value, 0)
                loaded += 1
            }
        }
        
        print("[EnvironmentLoader] Loaded \(loaded) variables from .env")
    }
    
    /// Find .env file in project root or app bundle
    private static func findEnvFile() -> String? {
        // Try project root (for development)
        let projectRoot = FileManager.default.currentDirectoryPath
        let projectEnv = (projectRoot as NSString).appendingPathComponent(".env")
        if FileManager.default.fileExists(atPath: projectEnv) {
            return projectEnv
        }
        
        // Try app bundle (for production)
        if let bundlePath = Bundle.main.bundlePath as String? {
            let bundleEnv = (bundlePath as NSString).appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: bundleEnv) {
                return bundleEnv
            }
            
            // Try parent directory (if .env is next to app)
            let parentEnv = ((bundlePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: parentEnv) {
                return parentEnv
            }
        }
        
        // Try home directory
        let homeEnv = (NSHomeDirectory() as NSString).appendingPathComponent(".cortex.env")
        if FileManager.default.fileExists(atPath: homeEnv) {
            return homeEnv
        }
        
        return nil
    }
}

