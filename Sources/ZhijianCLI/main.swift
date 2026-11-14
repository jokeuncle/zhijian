import Foundation
import DictionaryCore

do {
    try Commands.run(Array(CommandLine.arguments.dropFirst()))
} catch {
    let message = ["error": error.localizedDescription]
    print((try? LibraryJSON.string(message)) ?? "{\"error\":\"Unknown failure\"}")
    exit(1)
}
