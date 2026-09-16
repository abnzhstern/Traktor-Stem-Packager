// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TraktorStemPackager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TraktorStemPackager", targets: ["TraktorStemPackager"])
    ],
    targets: [
        .executableTarget(
            name: "TraktorStemPackager",
            path: "Sources/TraktorStemPackager"
        )
    ]
)
