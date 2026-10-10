import CryptoKit
import Foundation

@main enum UpdateFixtureSigner {
    static func main() throws {
        let key = Curve25519.Signing.PrivateKey()
        FileHandle.standardOutput.write(Data((key.publicKey.rawRepresentation.base64EncodedString() + "\n").utf8))
        while let path = readLine() {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            FileHandle.standardOutput.write(Data((try key.signature(for: bytes).base64EncodedString() + "\n").utf8))
        }
    }
}
