// The Swift Programming Language
// https://docs.swift.org/swift-book
import ArgumentParser
import CoreLocation
import Foundation
import SwiftCSV

@main
@available(macOS 11.0, *)
struct boulderbookDbManager: ParsableCommand {
    @Option(help: "CloudKit Key ID to use")
    public var CKKeyID: String
    
    @Option(help: "Private Key file path")
    public var privateKeyFilePath: String
    
    @Option(help: "CSV file path")
    public var csvFilePath: String
    
    public func run() throws {
        let csvfile = try CSV<Named>(url: URL(fileURLWithPath: self.csvFilePath))
        
        print(csvfile.rows.count)
        let loadedLocations = self.readCSVIntoLocations(csvfile)
        
        if loadedLocations.count >= 200 {
            print("Can't write over 200 operations. Code needs refactor.")
            throw ExitCode(1)
        }
        
        let ckConnector = CloudKitConnector(keyID: self.CKKeyID, privateKeyPath: self.privateKeyFilePath)
        
        for location in loadedLocations {
            ckConnector.writeLocation(location)
        }
    }
    
    private func readCSVIntoLocations(_ csvfile: CSV<Named>) -> [Location] {
        return csvfile.rows.map { location in
            let latitude = Double(location["latitude"]!)!
            let longitude = Double(location["longitude"]!)!
            
            return Location(
                id: UUID(uuidString: location["uuid"]!)!,
                country: location["country"]!,
                city: location["city"]!,
                name: location["name"]!,
                url: location["url"]!,
                latitude: latitude,
                longitude: longitude,
                status: location["status"]!)
        }
    }
}
