//
//  Models.swift
//  boulderbookDbManager
//
//  Created by Jose Antunes on 09/12/2023.
//

import Foundation
import CloudKit
import CryptoKit
import Network


struct Location: Identifiable, Encodable {
    var id: UUID
    
    var country: String
    var city: String
    var name: String
    var url: String
    var latitude: Double
    var longitude: Double
    var status: String
    
    init(
        id: UUID,
        country: String,
        city: String,
        name: String,
        url: String,
        latitude: Double,
        longitude: Double,
        status: String
    ) {
        self.id = id
        self.country = country
        self.city = city
        self.name = name
        self.url = url
        self.latitude = latitude
        self.longitude = longitude
        self.status = status
    }
}

struct DBOperationsMessage: Encodable {
    
    var operations: [DBRecordOperation]
    let zoneID: [String: String]
    let atomic: Bool
    let numbersAsStrings: Bool
    
    init(operations: DBRecordOperation) {
        self.operations = [operations]
        self.zoneID = [
            "zoneName": "_defaultZone"
        ]
        self.atomic = false
        self.numbersAsStrings = true
    }
    
}

struct DBRecordOperation: Encodable {
    let operationType: String
    let record: DBRecord
}

enum DBRecordFieldType: Encodable {
    case field(DBRecordField)
    case location(DBRecordFieldLocation)
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .field(let field):
            try container.encode(field)
        case .location(let location):
            try container.encode(location)
        }
    }
}

struct DBRecord: Encodable {
    let recordName: String
    let recordType: String
    let fields: [String:DBRecordFieldType]
}


// A record field dictionary represents the value of a field
// and is of the form { value: CKValue, type: string (optional) }.
// CKValue represents field values of type String, Number, Boolean, Reference, Asset, and Location.
struct DBRecordField: Encodable {
    let value: String?
    let type: String?
}

struct DBRecordFieldLocation: Encodable {
    let value: [String:String]
    let type: String = "LOCATION"
}

enum CloudKitConnectorError: Error {
    case invalidKeyPem
}

class CloudKitConnector {
    private var basePath = "https://api.apple-cloudkit.com"
    private var recordsPath = "/database/1/iCloud.rocks.boulderbook.bldrbk/development/public/records/modify"
    private var keyPem: String?
    
    public var keyID: String
    public var privateKeyPath: String
    
    init(keyID: String, privateKeyPath: String) {
        // Your server-to-server key from the CloudKit dashboard
        self.keyID = keyID
        self.privateKeyPath = privateKeyPath
        
        self.readKeyPem(privateKeyPath)
    }
    
    private func setHeaders(_ request: inout URLRequest, keyID: String, date: String, signature: String) {
        request.setValue(keyID, forHTTPHeaderField: "X-Apple-CloudKit-Request-KeyID")
        request.setValue(date, forHTTPHeaderField: "X-Apple-CloudKit-Request-ISO8601Date")
        request.setValue(signature, forHTTPHeaderField: "X-Apple-CloudKit-Request-SignatureV1")
    }
    
    private func getDateForHeaders() -> String {
        // set up ISO8601 date string, at UTC
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        return dateFormatter.string(from: Date())
    }
    
    private func readKeyPem(_ path: String) -> Void {
        let fileUrl = URL(fileURLWithPath: path)
        self.keyPem = try! String(contentsOf: fileUrl, encoding: .utf8)
    }
    
    @available(macOS 11.0, *)
    private func signRequestMessage(date: String, body: String, path: String) throws -> String {
        guard let actualKeyPem = self.keyPem else {
            throw CloudKitConnectorError.invalidKeyPem
        }
        
        let message = date + ":" + body + ":" + path
        // Set up the key and get ECDSA signature
        let privateKey = try? P256.Signing.PrivateKey(pemRepresentation: actualKeyPem)
        let sign = try? privateKey?.signature(for: SHA256.hash(data: message.data(using: .utf8)!))
        //let sign = try? privateKey?.signature(for: message.data(using: .utf8)!)
        return sign!.derRepresentation.base64EncodedString()
    }
    
    private func locationAsDBRecordFields(_ location: Location) -> [String:DBRecordFieldType] {
        let fields: [String:DBRecordFieldType] = [
            "country": .field(DBRecordField(value: location.country, type: "STRING")),
            "city": .field(DBRecordField(value: location.city, type: "STRING")),
            "name": .field(DBRecordField(value: location.name, type: "STRING")),
            "information_status": .field(DBRecordField(value: location.status, type: "STRING")),
            "url": .field(DBRecordField(value: location.url.lowercased(), type: "STRING")),
            "coordinates": .location(DBRecordFieldLocation(value: [
                "latitude": String(location.latitude),
                "longitude": String(location.longitude),
            ])),
            
        ]
        
        return fields
    }
    
    
    @available(macOS 11.0, *)
    func writeLocation(_ location: Location) {
        print("Trying to encode location")
        
        let operations = DBOperationsMessage(
            operations: DBRecordOperation(
                operationType: "forceUpdate",
                record: DBRecord(
                    recordName: location.id.uuidString,
                    recordType: "Location",
                    fields: self.locationAsDBRecordFields(location)
                )
            )
        )
        
        let encoder = JSONEncoder()
        let bodyData = try! encoder.encode(operations)
        print("Encoded location data")
        print(String(data: bodyData, encoding: .utf8)!)
        
        // hash then base64-encode the body
        let bodyHash = SHA256.hash(data: bodyData)
        let body64 = Data(bodyHash).base64EncodedString()
        
        let date = self.getDateForHeaders()
        // endpoint path you want to query
        let path = self.recordsPath
        // create the concatenated date, encoded body and subpath
        let signatureBase64 = try! self.signRequestMessage(date: date, body: body64, path: path)
        // Set up the full URI
        let url = URL(string: self.basePath + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Set CloudKit-required headers
        self.setHeaders(&request, keyID: self.keyID, date: date, signature: signatureBase64)
        // Our original body data for the request
        request.httpBody = bodyData
        
        // Create the request
        let session = URLSession.shared
        let sem = DispatchSemaphore.init(value: 0)
        let task = session.dataTask(with: request) { (data, response, error) in
            defer { sem.signal() }
            if let error {
                print(error)
            } else if let data {
                let json = try! JSONSerialization.jsonObject(with: data)
                print(json)
            } else {
                // Handle uncaught error
                print(response!)
            }
        }
        task.resume()
        sem.wait()
        print(task.response!)
    }
}

